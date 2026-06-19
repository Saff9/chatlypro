import { FastifyInstance, FastifyPluginOptions } from 'fastify';
import crypto from 'crypto';
import { pool } from '../db';
import { verifyToken } from './auth';
import { activeConnections, safeSend } from '../sockets/chat';

// ─── User Routes ──────────────────────────────────────────────────────────────
export async function userRoutes(fastify: FastifyInstance, _options: FastifyPluginOptions) {

  // GET /api/users/search?username=xxx — find users by username (auth required)
  fastify.get('/search', async (request, reply) => {
    const user = verifyToken(request.headers.authorization);
    if (!user) return reply.code(401).send({ error: 'Unauthorized' });

    const { username } = request.query as any;
    const q = typeof username === 'string' ? username.trim() : '';
    if (q.length < 2) {
      return reply.code(400).send({ error: 'Search query must be at least 2 characters' });
    }
    if (q.length > 30) {
      return reply.code(400).send({ error: 'Search query too long' });
    }

    try {
      const result = await pool.query(
        `SELECT id, username, avatar_color, bio, mood, tier
         FROM users
         WHERE LOWER(username) LIKE $1
           AND id != $2
         LIMIT 20`,
        [`%${q.toLowerCase()}%`, user.userId]
      );
      return reply.send({ users: result.rows });
    } catch (err: any) {
      fastify.log.error(err, 'GET /users/search: DB error');
      return reply.code(503).send({ error: 'Service temporarily unavailable' });
    }
  });

  // GET /api/users/profile — get own profile (auth required)
  fastify.get('/profile', async (request, reply) => {
    const user = verifyToken(request.headers.authorization);
    if (!user) return reply.code(401).send({ error: 'Unauthorized' });

    try {
      const result = await pool.query(
        `SELECT id, username, avatar_color, bio, mood, tier, email_verified, two_factor_enabled, created_at
         FROM users WHERE id = $1`,
        [user.userId]
      );
      if (result.rows.length === 0) return reply.code(404).send({ error: 'User not found' });
      return reply.send({ profile: result.rows[0] });
    } catch (err: any) {
      fastify.log.error(err, 'GET /users/profile: DB error');
      return reply.code(503).send({ error: 'Service temporarily unavailable' });
    }
  });

  // PUT /api/users/profile — update bio, mood, avatarColor (auth required)
  fastify.put('/profile', async (request, reply) => {
    const user = verifyToken(request.headers.authorization);
    if (!user) return reply.code(401).send({ error: 'Unauthorized' });

    const { username, bio, mood, avatarColor } = request.body as any;

    const updates: string[] = [];
    const values: any[]    = [];
    let idx = 1;

    if (username !== undefined) {
      if (typeof username !== 'string') return reply.code(400).send({ error: 'username must be a string' });
      const cleanUsername = username.toLowerCase().trim();
      if (cleanUsername.length < 3 || cleanUsername.length > 30 || !/^[a-zA-Z0-9_-]+$/.test(cleanUsername)) {
        return reply.code(400).send({ error: 'Username must be 3–30 characters and contain only letters, numbers, dashes and underscores' });
      }
      // Uniqueness check
      const checkRes = await pool.query('SELECT 1 FROM users WHERE username = $1 AND id != $2', [cleanUsername, user.userId]);
      if (checkRes.rows.length > 0) {
        return reply.code(400).send({ error: 'Username is already taken' });
      }
      updates.push(`username = $${idx++}`);
      values.push(cleanUsername);
    }
    if (bio !== undefined) {
      if (typeof bio !== 'string') return reply.code(400).send({ error: 'bio must be a string' });
      updates.push(`bio = $${idx++}`);
      values.push(bio.trim().slice(0, 100));
    }
    if (mood !== undefined) {
      if (typeof mood !== 'string') return reply.code(400).send({ error: 'mood must be a string' });
      updates.push(`mood = $${idx++}`);
      values.push(mood.trim().slice(0, 50));
    }
    if (avatarColor !== undefined) {
      // Only allow valid hex color codes
      if (typeof avatarColor !== 'string' || !/^#[0-9a-fA-F]{3,8}$/.test(avatarColor)) {
        return reply.code(400).send({ error: 'avatarColor must be a valid hex color' });
      }
      updates.push(`avatar_color = $${idx++}`);
      values.push(avatarColor);
    }

    if (updates.length === 0) {
      return reply.code(400).send({ error: 'No valid fields to update' });
    }

    values.push(user.userId);
    try {
      const result = await pool.query(
        `UPDATE users SET ${updates.join(', ')} WHERE id = $${idx} RETURNING id`,
        values
      );
      if (result.rowCount === 0) return reply.code(404).send({ error: 'User not found' });
      return reply.send({ success: true });
    } catch (err: any) {
      fastify.log.error(err, 'PUT /users/profile: DB error');
      return reply.code(503).send({ error: 'Update failed. Please try again.' });
    }
  });

  // GET /api/users/connections/pending — get pending connection requests for the current user
  fastify.get('/connections/pending', async (request, reply) => {
    const user = verifyToken(request.headers.authorization);
    if (!user) return reply.code(401).send({ error: 'Unauthorized' });

    try {
      const result = await pool.query(
        `SELECT u.username, u.avatar_color as "avatarColor", u.mood, u.bio
         FROM friendships f
         JOIN users u ON f.user_id_a = u.id
         WHERE f.user_id_b = $1 AND f.status = 'pending'`,
        [user.userId]
      );
      return reply.send({ requests: result.rows });
    } catch (err: any) {
      fastify.log.error(err, 'GET /users/connections/pending: DB error');
      return reply.code(503).send({ error: 'Service temporarily unavailable' });
    }
  });

  // POST /api/users/connect/:username — send connection request
  fastify.post('/connect/:username', async (request, reply) => {
    const user = verifyToken(request.headers.authorization);
    if (!user) return reply.code(401).send({ error: 'Unauthorized' });

    const { username } = request.params as any;
    const targetUsername = typeof username === 'string' ? username.toLowerCase().trim() : '';

    if (!targetUsername) {
      return reply.code(400).send({ error: 'Username is required' });
    }

    if (targetUsername === user.username.toLowerCase()) {
      return reply.code(400).send({ error: 'You cannot connect with yourself' });
    }

    try {
      // Find recipient user
      const targetRes = await pool.query('SELECT id FROM users WHERE LOWER(username) = $1', [targetUsername]);
      if (targetRes.rows.length === 0) {
        return reply.code(404).send({ error: 'User not found' });
      }
      const targetId = targetRes.rows[0].id;

      // Check if friendship exists
      const checkFriend = await pool.query(
        `SELECT status FROM friendships
         WHERE (user_id_a = $1 AND user_id_b = $2)
            OR (user_id_a = $2 AND user_id_b = $1)`,
        [user.userId, targetId]
      );

      if (checkFriend.rows.length > 0) {
        return reply.send({ success: true, message: 'Connection already exists or is pending' });
      }

      // Insert pending friendship: user.userId is user_id_a (sender)
      await pool.query(
        `INSERT INTO friendships (user_id_a, user_id_b, status)
         VALUES ($1, $2, 'pending')`,
        [user.userId, targetId]
      );

      // Notify target via WebSocket if online
      const targetSocket = activeConnections.get(targetUsername);
      if (targetSocket) {
        safeSend(targetSocket, JSON.stringify({
          type: 'incoming_connection_request',
          fromUsername: user.username,
        }));
      }

      return reply.send({ success: true, message: 'Connection request sent' });
    } catch (err: any) {
      fastify.log.error(err, 'POST /users/connect/:username: DB error');
      return reply.code(500).send({ error: 'Failed to send connection request' });
    }
  });

  // POST /api/users/connections/accept/:username — accept connection request
  fastify.post('/connections/accept/:username', async (request, reply) => {
    const user = verifyToken(request.headers.authorization);
    if (!user) return reply.code(401).send({ error: 'Unauthorized' });

    const { username } = request.params as any;
    const targetUsername = typeof username === 'string' ? username.toLowerCase().trim() : '';

    if (!targetUsername) {
      return reply.code(400).send({ error: 'Username is required' });
    }

    try {
      const targetRes = await pool.query('SELECT id FROM users WHERE LOWER(username) = $1', [targetUsername]);
      if (targetRes.rows.length === 0) {
        return reply.code(404).send({ error: 'User not found' });
      }
      const targetId = targetRes.rows[0].id;

      // Update friendship status to accepted
      const result = await pool.query(
        `UPDATE friendships
         SET status = 'accepted'
         WHERE user_id_a = $1 AND user_id_b = $2 AND status = 'pending'`,
        [targetId, user.userId] // targetId is sender, user.userId is receiver (us)
      );

      if (result.rowCount === 0) {
        return reply.code(400).send({ error: 'No pending request from this user' });
      }

      // Notify target via WebSocket if online that connection was accepted
      const targetSocket = activeConnections.get(targetUsername);
      if (targetSocket) {
        safeSend(targetSocket, JSON.stringify({
          type: 'connection_accepted',
          fromUsername: user.username,
        }));
      }

      return reply.send({ success: true, message: 'Connection request accepted' });
    } catch (err: any) {
      fastify.log.error(err, 'POST /users/connections/accept/:username: DB error');
      return reply.code(500).send({ error: 'Failed to accept connection request' });
    }
  });

  // POST /api/users/connections/reject/:username — reject connection request
  fastify.post('/connections/reject/:username', async (request, reply) => {
    const user = verifyToken(request.headers.authorization);
    if (!user) return reply.code(401).send({ error: 'Unauthorized' });

    const { username } = request.params as any;
    const targetUsername = typeof username === 'string' ? username.toLowerCase().trim() : '';

    if (!targetUsername) {
      return reply.code(400).send({ error: 'Username is required' });
    }

    try {
      const targetRes = await pool.query('SELECT id FROM users WHERE LOWER(username) = $1', [targetUsername]);
      if (targetRes.rows.length === 0) {
        return reply.code(404).send({ error: 'User not found' });
      }
      const targetId = targetRes.rows[0].id;

      // Delete friendship row
      const result = await pool.query(
        `DELETE FROM friendships
         WHERE user_id_a = $1 AND user_id_b = $2 AND status = 'pending'`,
        [targetId, user.userId] // targetId is sender, user.userId is receiver (us)
      );

      if (result.rowCount === 0) {
        return reply.code(400).send({ error: 'No pending request from this user' });
      }

      return reply.send({ success: true, message: 'Connection request rejected' });
    } catch (err: any) {
      fastify.log.error(err, 'POST /users/connections/reject/:username: DB error');
      return reply.code(500).send({ error: 'Failed to reject connection request' });
    }
  });
}

export async function groupRoutes(fastify: FastifyInstance, _options: FastifyPluginOptions) {
  setInterval(async () => {
    try {
      await pool.query('DELETE FROM groups WHERE expires_at IS NOT NULL AND expires_at < NOW()');
    } catch (_) {}
  }, 30000);

  fastify.get('/', async (request, reply) => {
    const user = verifyToken(request.headers.authorization);
    if (!user) return reply.code(401).send({ error: 'Unauthorized' });

    try {
      const result = await pool.query(
        `SELECT g.id, g.name, g.description, g.created_by, g.expires_at, g.created_at,
                (SELECT COUNT(*) FROM group_members WHERE group_id = g.id) as members_count
         FROM groups g
         JOIN group_members gm ON g.id = gm.group_id
         WHERE gm.user_id = $1`,
        [user.userId]
      );
      return reply.send({ groups: result.rows });
    } catch (err: any) {
      fastify.log.error(err, 'GET /groups: DB error');
      return reply.code(503).send({ error: 'Service temporarily unavailable' });
    }
  });

  fastify.post('/', async (request, reply) => {
    const user = verifyToken(request.headers.authorization);
    if (!user) return reply.code(401).send({ error: 'Unauthorized' });

    const { name, description, isCampfire, durationMs } = request.body as any;
    const cleanName = typeof name === 'string' ? name.trim() : '';

    if (!cleanName) {
      return reply.code(400).send({ error: 'Group name is required' });
    }

    try {
      if (!isCampfire) {
        const checkCreated = await pool.query(
          'SELECT COUNT(*) FROM groups WHERE created_by = $1 AND expires_at IS NULL',
          [user.userId]
        );
        const createdCount = parseInt(checkCreated.rows[0].count, 10);
        if (createdCount >= 25) {
          return reply.code(400).send({ error: 'Maximum permanent groups limit reached (25 groups max).' });
        }
      }

      const checkJoined = await pool.query(
        'SELECT COUNT(*) FROM group_members WHERE user_id = $1',
        [user.userId]
      );
      const joinedCount = parseInt(checkJoined.rows[0].count, 10);
      if (joinedCount >= 50) {
        return reply.code(400).send({ error: 'Maximum group memberships limit reached (50 groups max).' });
      }

      let expiresAt: Date | null = null;
      if (isCampfire) {
        const maxDuration = Math.min(Number(durationMs) || 60000, 86400000);
        expiresAt = new Date(Date.now() + maxDuration);
      }

      const newId = crypto.randomUUID();
      await pool.query(
        `INSERT INTO groups (id, name, description, created_by, expires_at)
         VALUES ($1, $2, $3, $4, $5)`,
        [newId, cleanName, description || '', user.userId, expiresAt]
      );

      await pool.query(
        `INSERT INTO group_members (group_id, user_id, role)
         VALUES ($1, $2, 'admin')`,
        [newId, user.userId]
      );

      return reply.code(201).send({
        group: {
          id: newId,
          name: cleanName,
          description,
          created_by: user.userId,
          expires_at: expiresAt,
          members_count: 1,
        }
      });
    } catch (err: any) {
      fastify.log.error(err, 'POST /groups: DB error');
      return reply.code(503).send({ error: 'Service temporarily unavailable' });
    }
  });

  fastify.post('/:id/join', async (request, reply) => {
    const user = verifyToken(request.headers.authorization);
    if (!user) return reply.code(401).send({ error: 'Unauthorized' });

    const { id } = request.params as any;

    try {
      const groupRes = await pool.query('SELECT expires_at FROM groups WHERE id = $1', [id]);
      if (groupRes.rows.length === 0) {
        return reply.code(404).send({ error: 'Group not found or dissolved' });
      }

      const expiresAt = groupRes.rows[0].expires_at;
      if (expiresAt && new Date(expiresAt) < new Date()) {
        return reply.code(404).send({ error: 'Group has been dissolved' });
      }

      const checkRes = await pool.query(
        'SELECT 1 FROM group_members WHERE group_id = $1 AND user_id = $2',
        [id, user.userId]
      );
      if (checkRes.rows.length > 0) {
        return reply.send({ success: true, message: 'Already a member' });
      }

      const checkJoined = await pool.query(
        'SELECT COUNT(*) FROM group_members WHERE user_id = $1',
        [user.userId]
      );
      const joinedCount = parseInt(checkJoined.rows[0].count, 10);
      if (joinedCount >= 50) {
        return reply.code(400).send({ error: 'Maximum group memberships limit reached (50 groups max).' });
      }

      await pool.query(
        `INSERT INTO group_members (group_id, user_id, role)
         VALUES ($1, $2, 'member')`,
        [id, user.userId]
      );

      return reply.send({ success: true });
    } catch (err: any) {
      fastify.log.error(err, 'POST /groups/:id/join: DB error');
      return reply.code(503).send({ error: 'Service temporarily unavailable' });
    }
  });

  // POST /api/groups/:id/keys — Store an ECIES-wrapped group key for a specific member.
  // Caller must be a group member. Used by the group creator (or any member) to share
  // the plaintext group key with a new invitee encrypted under their DH identity key.
  fastify.post('/:id/keys', async (request, reply) => {
    const user = verifyToken(request.headers.authorization);
    if (!user) return reply.code(401).send({ error: 'Unauthorized' });

    const { id } = request.params as any;
    const { username, encrypted_key } = request.body as any;

    if (!username || typeof username !== 'string' || !encrypted_key || typeof encrypted_key !== 'string') {
      return reply.code(400).send({ error: 'username and encrypted_key are required' });
    }
    if (encrypted_key.length > 4096) {
      return reply.code(400).send({ error: 'encrypted_key too large' });
    }

    try {
      // Verify caller is a group member
      const callerRes = await pool.query(
        'SELECT 1 FROM group_members WHERE group_id = $1 AND user_id = $2',
        [id, user.userId]
      );
      if (callerRes.rows.length === 0) {
        return reply.code(403).send({ error: 'Forbidden: Not a group member' });
      }

      // Resolve target user
      const targetRes = await pool.query(
        'SELECT id FROM users WHERE LOWER(username) = $1',
        [username.toLowerCase().trim()]
      );
      if (targetRes.rows.length === 0) {
        return reply.code(404).send({ error: 'Target user not found' });
      }
      const targetId = targetRes.rows[0].id;

      await pool.query(
        `INSERT INTO group_keys (group_id, user_id, encrypted_key, updated_at)
         VALUES ($1, $2, $3, NOW())
         ON CONFLICT (group_id, user_id)
         DO UPDATE SET encrypted_key = $3, updated_at = NOW()`,
        [id, targetId, encrypted_key]
      );

      return reply.send({ success: true });
    } catch (err: any) {
      fastify.log.error(err, 'POST /groups/:id/keys: DB error');
      return reply.code(503).send({ error: 'Service temporarily unavailable' });
    }
  });

  // GET /api/groups/:id/keys/my — Retrieve the ECIES-wrapped group key for the requesting user.
  fastify.get('/:id/keys/my', async (request, reply) => {
    const user = verifyToken(request.headers.authorization);
    if (!user) return reply.code(401).send({ error: 'Unauthorized' });

    const { id } = request.params as any;

    try {
      // Verify membership
      const memberRes = await pool.query(
        'SELECT 1 FROM group_members WHERE group_id = $1 AND user_id = $2',
        [id, user.userId]
      );
      if (memberRes.rows.length === 0) {
        return reply.code(403).send({ error: 'Forbidden: Not a group member' });
      }

      const keyRes = await pool.query(
        'SELECT encrypted_key FROM group_keys WHERE group_id = $1 AND user_id = $2',
        [id, user.userId]
      );

      if (keyRes.rows.length === 0) {
        return reply.code(404).send({ error: 'Group key not available. Ask a group member to re-invite you.' });
      }

      return reply.send({ encrypted_key: keyRes.rows[0].encrypted_key });
    } catch (err: any) {
      fastify.log.error(err, 'GET /groups/:id/keys/my: DB error');
      return reply.code(503).send({ error: 'Service temporarily unavailable' });
    }
  });

  fastify.get('/:id/messages', async (request, reply) => {
    const user = verifyToken(request.headers.authorization);
    if (!user) return reply.code(401).send({ error: 'Unauthorized' });

    const { id } = request.params as any;

    try {
      const memberRes = await pool.query(
        'SELECT 1 FROM group_members WHERE group_id = $1 AND user_id = $2',
        [id, user.userId]
      );
      if (memberRes.rows.length === 0) {
        return reply.code(403).send({ error: 'Forbidden: You are not a member of this group' });
      }

      const msgs = await pool.query(
        `SELECT gm.id, u.username as sender, gm.ciphertext, gm.created_at
         FROM group_messages gm
         JOIN users u ON gm.sender_id = u.id
         WHERE gm.group_id = $1
         ORDER BY gm.created_at ASC
         LIMIT 100`,
        [id]
      );
      return reply.send({ messages: msgs.rows });
    } catch (err: any) {
      fastify.log.error(err, 'GET /groups/:id/messages: DB error');
      return reply.code(503).send({ error: 'Service temporarily unavailable' });
    }
  });

  // GET /api/groups/:id/members — list usernames for a group (auth + membership required)
  fastify.get('/:id/members', async (request, reply) => {
    const user = verifyToken(request.headers.authorization);
    if (!user) return reply.code(401).send({ error: 'Unauthorized' });

    const { id } = request.params as any;
    try {
      const memberRes = await pool.query(
        'SELECT 1 FROM group_members WHERE group_id = $1 AND user_id = $2',
        [id, user.userId]
      );
      if (memberRes.rows.length === 0) {
        return reply.code(403).send({ error: 'Forbidden' });
      }
      const result = await pool.query(
        `SELECT u.username FROM group_members gm
         JOIN users u ON gm.user_id = u.id
         WHERE gm.group_id = $1`,
        [id]
      );
      return reply.send({ members: result.rows.map((r: any) => r.username) });
    } catch (err: any) {
      fastify.log.error(err, 'GET /groups/:id/members: DB error');
      return reply.code(503).send({ error: 'Service temporarily unavailable' });
    }
  });

  // ─── Signal Sender Key Distribution ────────────────────────────────────────
  // POST /api/groups/:id/sender-key — upload encrypted sender key bundles
  // Body: { bundles: [{ recipientUsername: string, encryptedBundle: string }] }
  // Each bundle is the caller's SenderKey encrypted for a specific group member.
  // The server stores opaque ciphertext and cannot read any bundle.
  fastify.post('/:id/sender-key', async (request, reply) => {
    const user = verifyToken(request.headers.authorization);
    if (!user) return reply.code(401).send({ error: 'Unauthorized' });

    const { id } = request.params as any;
    const { bundles } = request.body as any;

    if (!Array.isArray(bundles) || bundles.length === 0) {
      return reply.code(400).send({ error: 'bundles array is required' });
    }
    if (bundles.length > 100) {
      return reply.code(400).send({ error: 'Too many bundles (max 100)' });
    }

    try {
      // Verify sender is a group member
      const memberCheck = await pool.query(
        'SELECT 1 FROM group_members WHERE group_id = $1 AND user_id = $2',
        [id, user.userId]
      );
      if (memberCheck.rows.length === 0) {
        return reply.code(403).send({ error: 'Forbidden' });
      }

      for (const bundle of bundles) {
        const recipientUsername = typeof bundle.recipientUsername === 'string'
          ? bundle.recipientUsername.toLowerCase().trim() : '';
        const encryptedBundle = typeof bundle.encryptedBundle === 'string'
          ? bundle.encryptedBundle : '';

        if (!recipientUsername || !encryptedBundle) continue;
        if (encryptedBundle.length > 8192) continue; // 8 KB max per bundle

        // Resolve recipient UUID
        const recipientRes = await pool.query(
          'SELECT id FROM users WHERE LOWER(username) = $1',
          [recipientUsername]
        );
        if (recipientRes.rows.length === 0) continue;
        const recipientId = recipientRes.rows[0].id;

        await pool.query(
          `INSERT INTO group_sender_keys (group_id, sender_id, recipient_id, encrypted_bundle, updated_at)
           VALUES ($1, $2, $3, $4, NOW())
           ON CONFLICT (group_id, sender_id, recipient_id) DO UPDATE
             SET encrypted_bundle = EXCLUDED.encrypted_bundle,
                 updated_at = NOW()`,
          [id, user.userId, recipientId, encryptedBundle]
        );
      }

      return reply.send({ success: true });
    } catch (err: any) {
      fastify.log.error(err, 'POST /groups/:id/sender-key: DB error');
      return reply.code(503).send({ error: 'Service temporarily unavailable' });
    }
  });

  // GET /api/groups/:id/sender-key/:senderUsername
  // Returns the encrypted SenderKey bundle that senderUsername uploaded for the requesting user.
  fastify.get('/:id/sender-key/:senderUsername', async (request, reply) => {
    const user = verifyToken(request.headers.authorization);
    if (!user) return reply.code(401).send({ error: 'Unauthorized' });

    const { id, senderUsername } = request.params as any;

    try {
      // Verify requester is a group member
      const memberCheck = await pool.query(
        'SELECT 1 FROM group_members WHERE group_id = $1 AND user_id = $2',
        [id, user.userId]
      );
      if (memberCheck.rows.length === 0) {
        return reply.code(403).send({ error: 'Forbidden' });
      }

      // Resolve sender UUID
      const senderRes = await pool.query(
        'SELECT id FROM users WHERE LOWER(username) = $1',
        [senderUsername.toLowerCase().trim()]
      );
      if (senderRes.rows.length === 0) {
        return reply.code(404).send({ error: 'Sender not found' });
      }
      const senderId = senderRes.rows[0].id;

      const result = await pool.query(
        `SELECT encrypted_bundle FROM group_sender_keys
         WHERE group_id = $1 AND sender_id = $2 AND recipient_id = $3`,
        [id, senderId, user.userId]
      );

      if (result.rows.length === 0) {
        return reply.code(404).send({ found: false });
      }

      return reply.send({
        found: true,
        encryptedBundle: result.rows[0].encrypted_bundle,
      });
    } catch (err: any) {
      fastify.log.error(err, 'GET /groups/:id/sender-key/:senderUsername: DB error');
      return reply.code(503).send({ error: 'Service temporarily unavailable' });
    }
  });
}
