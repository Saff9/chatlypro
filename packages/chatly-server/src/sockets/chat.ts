import { WebSocket } from 'ws';
import jwt from 'jsonwebtoken';
import { redisClient, scanKeys } from '../db/redis';
import { pool } from '../db';
import { sendSilentPush } from '../services/push';
import { inMemoryPushTokens, inMemoryUsers } from '../routes/auth';

const JWT_SECRET = process.env.JWT_SECRET || 'chatly-super-secret-key-change-in-prod';
const NODE_ENV = process.env.NODE_ENV || 'development';

if (NODE_ENV === 'production' && JWT_SECRET === 'chatly-super-secret-key-change-in-prod') {
  console.error('[FATAL] JWT_SECRET must be set to a strong random value in production. Refusing to start.');
  process.exit(1);
}

// Active sockets map
const activeConnections = new Map<string, WebSocket>();

// In-memory fallback for offline messages if Redis isn't loaded
interface TempMessage {
  id: string;
  senderId: string;
  recipientId: string;
  ciphertext: string;
  timestamp: number;
}
const inMemoryOfflineQueue: TempMessage[] = [];

// Cleanup memory offline queue every 10 minutes to prevent memory leaks
setInterval(() => {
  const cutoff = Date.now() - 24 * 60 * 60 * 1000; // 24 hours
  let i = inMemoryOfflineQueue.length;
  while (i--) {
    if (inMemoryOfflineQueue[i].timestamp < cutoff) {
      inMemoryOfflineQueue.splice(i, 1);
    }
  }
}, 600000);

export async function handleWebSocketConnection(socket: WebSocket, req: any) {
  // Extract token from Authorization header or fallback to query params
  const authHeader = req.headers['authorization'];
  let token: string | null = null;
  if (authHeader && authHeader.startsWith('Bearer ')) {
    token = authHeader.split(' ')[1];
  } else {
    const url = new URL(req.url, 'http://localhost');
    token = url.searchParams.get('token');
  }

  if (!token) {
    socket.close(4001, 'Unauthorized: Missing token');
    return;
  }

  let userId: string;
  let username: string;
  let tokenEmailVerified = false;

  try {
    const decoded = jwt.verify(token, JWT_SECRET) as { userId: string; username: string; emailVerified?: boolean };
    userId = decoded.userId;
    username = decoded.username;
    tokenEmailVerified = !!decoded.emailVerified;
  } catch (err) {
    socket.close(4002, 'Unauthorized: Invalid token');
    return;
  }

  // Check email verification status
  let emailVerified = tokenEmailVerified;
  try {
    const result = await pool.query('SELECT email_verified FROM users WHERE id = $1', [userId]);
    if (result.rows.length > 0) {
      emailVerified = result.rows[0].email_verified;
    } else {
      const memoryUser = inMemoryUsers.find(u => u.id === userId);
      if (memoryUser) {
        emailVerified = memoryUser.emailVerified;
      }
    }
  } catch (err: any) {
    console.warn('Postgres connection failed during WS auth, relying on token emailVerified state:', err.message);
  }

  if (!emailVerified) {
    socket.close(4003, 'Unauthorized: Email not verified');
    return;
  }

  // Register socket (close old connection for this user if exists to prevent duplicate connection DOS)
  const existingSocket = activeConnections.get(username);
  if (existingSocket) {
    existingSocket.close(4009, 'New connection established elsewhere');
  }
  activeConnections.set(username, socket);
  console.log(`User ${username} (${userId}) connected via WebSocket.`);

  // Set online status in Redis / Fallback (active flag)
  await redisClient.set(`presence:${userId}`, 'online', 'EX', 30);

  // Deliver offline queue immediately
  await deliverOfflineMessages(username, socket);

  // Heartbeat interval to maintain connection status
  const presenceInterval = setInterval(async () => {
    if (socket.readyState === WebSocket.OPEN) {
      await redisClient.set(`presence:${userId}`, 'online', 'EX', 30);
    }
  }, 15000);

  let messageCount = 0;
  let resetTime = Date.now() + 60000;

  // Listen to messages
  socket.on('message', async (data) => {
    // 64KB Max Message Size check to prevent payload size DOS
    if (data.toString().length > 65536) {
      console.warn(`WebSocket message size exceeded limit from user ${username}`);
      socket.close(1009, 'Message too big');
      return;
    }

    // Rate Limiting: max 120 messages per minute
    const now = Date.now();
    if (now > resetTime) {
      messageCount = 0;
      resetTime = now + 60000;
    }
    messageCount++;
    if (messageCount > 120) {
      console.warn(`WebSocket rate limit exceeded for user ${username}`);
      socket.close(1008, 'Rate limit exceeded');
      return;
    }

    try {
      const message = JSON.parse(data.toString());
      
      switch (message.type) {
        case 'ping':
          socket.send(JSON.stringify({ type: 'pong' }));
          break;
          
        case 'message':
          // Relay E2E Ciphertext
          await relayE2EMessage(username, message.recipientId, message.ciphertext);
          break;

        case 'typing':
          // Relay typing indicator
          await relayTypingIndicator(username, message.recipientId, message.isTyping);
          break;

        default:
          console.warn('Unknown message type:', message.type);
      }
    } catch (err) {
      console.error('WebSocket message handling error:', err);
    }
  });

  // Socket close / cleanup
  socket.on('close', () => {
    activeConnections.delete(username);
    clearInterval(presenceInterval);
    redisClient.del(`presence:${userId}`);
    console.log(`User ${username} (${userId}) disconnected.`);
  });

  socket.on('error', (err) => {
    console.error(`Socket error for user ${username}:`, err);
  });
}

// Deliver offline messages cached in Redis / Memory
async function deliverOfflineMessages(recipientId: string, socket: WebSocket) {
  try {
    // 1. Check Redis keys in a non-blocking way
    const keys = await scanKeys(`msg:${recipientId}:*`);
    if (keys.length > 0) {
      console.log(`Delivering ${keys.length} offline messages to ${recipientId} via Redis...`);
      for (const key of keys) {
        const data = await redisClient.get(key);
        if (data) {
          socket.send(JSON.stringify({ type: 'message', data: JSON.parse(data) }));
        }
        await redisClient.del(key); // DELETE after delivery (Zero trace)
      }
      return;
    }
  } catch (err) {
    console.error('Error fetching from Redis offline queue:', err);
  }

  // 2. Memory Fallback check
  const myOfflineMsgs = inMemoryOfflineQueue.filter(m => m.recipientId === recipientId);
  if (myOfflineMsgs.length > 0) {
    console.log(`Delivering ${myOfflineMsgs.length} offline messages to ${recipientId} via Memory...`);
    for (const msg of myOfflineMsgs) {
      socket.send(JSON.stringify({
        type: 'message',
        senderId: msg.senderId,
        ciphertext: msg.ciphertext,
        timestamp: msg.timestamp
      }));
      // Remove from memory queue (Zero trace)
      const index = inMemoryOfflineQueue.indexOf(msg);
      if (index > -1) {
        inMemoryOfflineQueue.splice(index, 1);
      }
    }
  }
}

// Relay message
async function relayE2EMessage(senderId: string, recipientId: string, ciphertext: string) {
  const recipientSocket = activeConnections.get(recipientId);

  const payload = {
    senderId,
    ciphertext,
    timestamp: Date.now()
  };

  if (recipientSocket && recipientSocket.readyState === WebSocket.OPEN) {
    // Recipient is online: Relay immediately
    recipientSocket.send(JSON.stringify({ type: 'message', ...payload }));
    console.log(`Relayed message from ${senderId} to ${recipientId} immediately (Zero disk write).`);
  } else {
    // Recipient is offline: Cache temporarily (up to 24h TTL)
    const msgId = crypto.randomUUID ? crypto.randomUUID() : Math.random().toString(36).substring(2);
    try {
      await redisClient.set(
        `msg:${recipientId}:${msgId}`, 
        JSON.stringify(payload), 
        'EX', 
        86400 // 24 hours TTL
      );
      console.log(`Saved offline message to Redis for ${recipientId} (TTL: 24h).`);
    } catch (err) {
      // In-Memory cache fallback: Cap at 100 messages per recipient to prevent memory leaks/DoS
      const recipientCount = inMemoryOfflineQueue.filter(m => m.recipientId === recipientId).length;
      if (recipientCount < 100) {
        inMemoryOfflineQueue.push({
          id: msgId,
          senderId,
          recipientId,
          ciphertext,
          timestamp: payload.timestamp
        });
        console.log(`Saved offline message to Memory fallback for ${recipientId} (TTL: 24h simulated).`);
      } else {
        console.warn(`In-memory offline queue for ${recipientId} reached capacity limit (100). Dropping message.`);
      }
    }

    // Trigger silent push notification
    try {
      let pushToken: string | undefined;
      const memoryUser = inMemoryUsers.find(u => u.username === recipientId);
      if (memoryUser) {
        pushToken = inMemoryPushTokens.get(memoryUser.id);
      }

      if (!pushToken) {
        const res = await pool.query('SELECT push_token FROM users WHERE username = $1', [recipientId]);
        if (res.rows.length > 0 && res.rows[0].push_token) {
          pushToken = res.rows[0].push_token;
        }
      }
      
      if (pushToken) {
        await sendSilentPush(pushToken, msgId);
      } else {
        console.log(`No push token registered for offline user ${recipientId}.`);
      }
    } catch (err: any) {
      console.warn(`Failed to retrieve push token for offline user ${recipientId}:`, err.message);
    }
  }
}

// Relay typing status
async function relayTypingIndicator(senderId: string, recipientId: string, isTyping: boolean) {
  const recipientSocket = activeConnections.get(recipientId);
  if (recipientSocket && recipientSocket.readyState === WebSocket.OPEN) {
    recipientSocket.send(JSON.stringify({
      type: 'typing',
      senderId,
      isTyping
    }));
  }
}
