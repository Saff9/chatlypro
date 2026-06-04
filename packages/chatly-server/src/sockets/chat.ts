import { WebSocket } from 'ws';
import crypto from 'crypto';
import jwt from 'jsonwebtoken';
import { redisClient, scanKeys } from '../db/redis';
import { pool } from '../db';
import { sendSilentPush } from '../services/push';

const JWT_SECRET = process.env.JWT_SECRET!;

// ─── Active socket registry ───────────────────────────────────────────────────
// Keyed by username (unique per user). Incoming connections replace old ones.
export const activeConnections = new Map<string, WebSocket>();

// ─── In-memory offline message queue (Redis fallback only) ───────────────────
interface OfflineMessage {
  id: string;
  senderId: string;
  recipientId: string;
  ciphertext: string;
  timestamp: number;
}
const inMemoryOfflineQueue: OfflineMessage[] = [];

// Purge messages older than 24h every 10 minutes to prevent unbounded memory growth
setInterval(() => {
  const cutoff = Date.now() - 86_400_000;
  let i = inMemoryOfflineQueue.length;
  while (i--) {
    if (inMemoryOfflineQueue[i].timestamp < cutoff) {
      inMemoryOfflineQueue.splice(i, 1);
    }
  }
}, 600_000);

// ─── WebSocket Connection Handler ─────────────────────────────────────────────
export async function handleWebSocketConnection(socket: WebSocket, req: any) {
  // Token can come from Authorization header or ?token= query param
  const authHeader = req.headers['authorization'];
  let token: string | null = null;

  if (authHeader?.startsWith('Bearer ')) {
    token = authHeader.slice(7);
  } else {
    try {
      const url = new URL(req.url, 'http://localhost');
      token = url.searchParams.get('token');
    } catch {
      // ignore malformed URLs
    }
  }

  if (!token) {
    socket.close(4001, 'Unauthorized: Missing token');
    return;
  }

  let userId: string;
  let username: string;
  let tokenEmailVerified = false;

  try {
    const decoded = jwt.verify(token, JWT_SECRET) as {
      userId: string;
      username: string;
      emailVerified?: boolean;
    };
    userId   = decoded.userId;
    username = decoded.username;
    tokenEmailVerified = !!decoded.emailVerified;
  } catch {
    socket.close(4002, 'Unauthorized: Invalid token');
    return;
  }

  // Verify email verification status from DB (don't trust token alone)
  let emailVerified = tokenEmailVerified;
  try {
    const result = await pool.query('SELECT email_verified FROM users WHERE id = $1', [userId]);
    if (result.rows.length > 0) {
      emailVerified = result.rows[0].email_verified;
    } else {
      // User doesn't exist in DB
      socket.close(4004, 'Unauthorized: User not found');
      return;
    }
  } catch (err: any) {
    // DB unavailable — fall back to token claim, but log the issue
    console.warn('[WS] DB check failed, trusting token emailVerified claim:', err.message);
  }

  if (!emailVerified) {
    socket.close(4003, 'Unauthorized: Email not verified');
    return;
  }

  // Close existing connection for this user (prevent duplicate connections / DoS)
  const existing = activeConnections.get(username);
  if (existing && existing.readyState === WebSocket.OPEN) {
    existing.close(4009, 'Replaced by new connection');
  }
  activeConnections.set(username, socket);
  console.log(`[WS] ${username} (${userId}) connected`);

  // Set online presence in Redis with 30s TTL
  await redisClient.set(`presence:${userId}`, 'online', 'EX', 30).catch(() => {});

  // Deliver any queued offline messages
  await deliverOfflineMessages(username, socket);

  // Heartbeat: refresh online presence every 15s
  const presenceInterval = setInterval(async () => {
    if (socket.readyState === WebSocket.OPEN) {
      await redisClient.set(`presence:${userId}`, 'online', 'EX', 30).catch(() => {});
    }
  }, 15_000);

  // Per-socket rate limit: max 120 messages/minute
  let messageCount = 0;
  let rateLimitResetAt = Date.now() + 60_000;

  socket.on('message', async (data) => {
    // Guard against oversized payloads (64 KB)
    if (Buffer.byteLength(data as any) > 65_536) {
      socket.close(1009, 'Message too large');
      return;
    }

    // Rate limit
    const now = Date.now();
    if (now > rateLimitResetAt) {
      messageCount = 0;
      rateLimitResetAt = now + 60_000;
    }
    if (++messageCount > 120) {
      socket.close(1008, 'Rate limit exceeded');
      return;
    }

    let message: any;
    try {
      message = JSON.parse(data.toString());
    } catch {
      socket.send(JSON.stringify({ type: 'error', error: 'Invalid JSON' }));
      return;
    }

    switch (message.type) {
      case 'ping':
        socket.send(JSON.stringify({ type: 'pong' }));
        break;

      case 'message':
        if (!message.recipientId || !message.ciphertext) {
          socket.send(JSON.stringify({ type: 'error', error: 'recipientId and ciphertext are required' }));
          break;
        }
        // Enforce max ciphertext size (100 KB)
        if (typeof message.ciphertext !== 'string' || message.ciphertext.length > 102_400) {
          socket.send(JSON.stringify({ type: 'error', error: 'ciphertext too large' }));
          break;
        }
        await relayE2EMessage(username, String(message.recipientId), String(message.ciphertext));
        break;

      case 'typing':
        if (!message.recipientId) break;
        relayTypingIndicator(username, String(message.recipientId), !!message.isTyping);
        break;

      case 'group_message':
        if (!message.groupId || !message.ciphertext) {
          socket.send(JSON.stringify({ type: 'error', error: 'groupId and ciphertext are required' }));
          break;
        }
        if (typeof message.ciphertext !== 'string' || message.ciphertext.length > 102_400) {
          socket.send(JSON.stringify({ type: 'error', error: 'ciphertext too large' }));
          break;
        }
        await relayGroupMessage(username, String(message.groupId), String(message.ciphertext));
        break;

      default:
        socket.send(JSON.stringify({ type: 'error', error: `Unknown message type: ${message.type}` }));
    }
  });

  socket.on('close', () => {
    // Only remove if this is still the active socket for this user
    if (activeConnections.get(username) === socket) {
      activeConnections.delete(username);
    }
    clearInterval(presenceInterval);
    redisClient.del(`presence:${userId}`).catch(() => {});
    console.log(`[WS] ${username} (${userId}) disconnected`);
  });

  socket.on('error', (err) => {
    console.error(`[WS] Socket error for ${username}:`, err.message);
  });
}

// ─── Deliver Offline Messages ──────────────────────────────────────────────────
async function deliverOfflineMessages(recipientUsername: string, socket: WebSocket) {
  // Try Redis first
  try {
    const keys = await scanKeys(`msg:${recipientUsername}:*`);
    if (keys.length > 0) {
      for (const key of keys) {
        const data = await redisClient.get(key);
        if (data) {
          try {
            socket.send(JSON.stringify({ type: 'message', data: JSON.parse(data) }));
          } catch {
            // Skip malformed cached message
          }
        }
        await redisClient.del(key);
      }
      return;
    }
  } catch (err: any) {
    console.warn('[WS] Redis offline fetch failed, trying memory:', err.message);
  }

  // Memory fallback
  const pending = inMemoryOfflineQueue.filter(m => m.recipientId === recipientUsername);
  for (const msg of pending) {
    socket.send(JSON.stringify({
      type: 'message',
      senderId: msg.senderId,
      ciphertext: msg.ciphertext,
      timestamp: msg.timestamp,
    }));
    const idx = inMemoryOfflineQueue.indexOf(msg);
    if (idx > -1) inMemoryOfflineQueue.splice(idx, 1);
  }
}

// ─── Relay E2E Encrypted Message ──────────────────────────────────────────────
async function relayE2EMessage(senderUsername: string, recipientUsername: string, ciphertext: string) {
  const recipientSocket = activeConnections.get(recipientUsername);
  const payload = { senderId: senderUsername, ciphertext, timestamp: Date.now() };

  if (recipientSocket?.readyState === WebSocket.OPEN) {
    recipientSocket.send(JSON.stringify({ type: 'message', ...payload }));
    return;
  }

  // Recipient offline — queue message
  const msgId = crypto.randomUUID();
  const stored = await redisClient.set(
    `msg:${recipientUsername}:${msgId}`,
    JSON.stringify(payload),
    'EX', 86_400 // 24h TTL
  ).catch(() => null);

  if (!stored) {
    // Redis unavailable — use bounded memory queue (max 100 per recipient)
    const count = inMemoryOfflineQueue.filter(m => m.recipientId === recipientUsername).length;
    if (count < 100) {
      inMemoryOfflineQueue.push({ id: msgId, senderId: senderUsername, recipientId: recipientUsername, ciphertext, timestamp: payload.timestamp });
    } else {
      console.warn(`[WS] Offline queue full for ${recipientUsername} — message dropped`);
    }
  }

  // Trigger silent push notification to wake up recipient's device
  try {
    const res = await pool.query('SELECT push_token FROM users WHERE username = $1', [recipientUsername]);
    const pushToken = res.rows[0]?.push_token;
    if (pushToken) {
      await sendSilentPush(pushToken, msgId);
    }
  } catch (err: any) {
    console.warn(`[WS] Push notification failed for ${recipientUsername}:`, err.message);
  }
}

// ─── Relay Typing Indicator ────────────────────────────────────────────────────
function relayTypingIndicator(senderUsername: string, recipientUsername: string, isTyping: boolean) {
  const recipientSocket = activeConnections.get(recipientUsername);
  if (recipientSocket?.readyState === WebSocket.OPEN) {
    recipientSocket.send(JSON.stringify({ type: 'typing', senderId: senderUsername, isTyping }));
  }
}

// ─── Relay E2E Encrypted Group Message ──────────────────────────────────────────
async function relayGroupMessage(senderUsername: string, groupId: string, ciphertext: string) {
  try {
    const senderRes = await pool.query('SELECT id FROM users WHERE username = $1', [senderUsername]);
    if (senderRes.rows.length === 0) return;
    const senderId = senderRes.rows[0].id;

    await pool.query(
      'INSERT INTO group_messages (group_id, sender_id, text) VALUES ($1, $2, $3)',
      [groupId, senderId, ciphertext]
    );

    const membersRes = await pool.query(
      'SELECT u.username FROM group_members gm JOIN users u ON gm.user_id = u.id WHERE gm.group_id = $1',
      [groupId]
    );

    const payload = {
      type: 'group_message',
      groupId,
      senderId: senderUsername,
      ciphertext,
      timestamp: Date.now(),
    };

    for (const row of membersRes.rows) {
      const memberUsername = row.username;
      if (memberUsername === senderUsername) continue;

      const memberSocket = activeConnections.get(memberUsername);
      if (memberSocket?.readyState === WebSocket.OPEN) {
        memberSocket.send(JSON.stringify(payload));
      } else {
        try {
          const pushRes = await pool.query('SELECT push_token FROM users WHERE username = $1', [memberUsername]);
          const pushToken = pushRes.rows[0]?.push_token;
          if (pushToken) {
            await sendSilentPush(pushToken, `group-msg-${groupId}-${Date.now()}`);
          }
        } catch (_) {}
      }
    }
  } catch (err: any) {
    console.error('[WS] relayGroupMessage error:', err.message);
  }
}
