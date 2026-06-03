import { FastifyInstance, FastifyPluginOptions } from 'fastify';
import crypto from 'crypto';
import { pool } from '../db';
import { verifyToken } from './auth';

// ─── Pulse Routes ─────────────────────────────────────────────────────────────
export async function pulseRoutes(fastify: FastifyInstance, _options: FastifyPluginOptions) {

  // GET /api/pulse — newest first, max 50, within 7 days
  fastify.get('/', async (request, reply) => {
    try {
      const result = await pool.query(
        `SELECT id, text, topics, seen_count, replies_count, created_at
         FROM pulse_posts
         WHERE created_at > NOW() - INTERVAL '7 days'
         ORDER BY created_at DESC
         LIMIT 50`
      );
      return reply.send({ pulses: result.rows });
    } catch (err: any) {
      fastify.log.error(err, 'GET /pulse: DB error');
      return reply.code(503).send({ error: 'Service temporarily unavailable' });
    }
  });

  // POST /api/pulse — create anonymous pulse (auth required)
  fastify.post('/', async (request, reply) => {
    const user = verifyToken(request.headers.authorization);
    if (!user) return reply.code(401).send({ error: 'Unauthorized' });

    const { text, topics } = request.body as any;
    const cleanText = typeof text === 'string' ? text.trim() : '';

    if (!cleanText) {
      return reply.code(400).send({ error: 'Pulse text is required' });
    }
    if (cleanText.length > 200) {
      return reply.code(400).send({ error: 'Pulse text must be 200 characters or fewer' });
    }

    const topicsArray: string[] = Array.isArray(topics)
      ? topics.map((t: any) => String(t).trim()).filter(Boolean).slice(0, 5)
      : typeof topics === 'string'
        ? topics.split(' ').map(t => t.trim()).filter(Boolean).slice(0, 5)
        : [];

    const newId = crypto.randomUUID();

    try {
      const result = await pool.query(
        `INSERT INTO pulse_posts (id, author_id, text, topics, seen_count, replies_count)
         VALUES ($1, $2, $3, $4, 0, 0)
         RETURNING id, text, topics, seen_count, replies_count, created_at`,
        [newId, user.userId, cleanText, JSON.stringify(topicsArray)]
      );
      return reply.code(201).send({ pulse: result.rows[0] });
    } catch (err: any) {
      fastify.log.error(err, 'POST /pulse: DB error');
      return reply.code(503).send({ error: 'Service temporarily unavailable' });
    }
  });

  // POST /api/pulse/:id/seen — increment seen count (no auth required, fire-and-forget)
  fastify.post('/:id/seen', async (request, reply) => {
    const { id } = request.params as any;

    // Validate UUID format to prevent injection
    const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!UUID_RE.test(id)) {
      return reply.code(400).send({ error: 'Invalid id' });
    }

    try {
      await pool.query('UPDATE pulse_posts SET seen_count = seen_count + 1 WHERE id = $1', [id]);
    } catch (err: any) {
      fastify.log.error(err, 'POST /pulse/:id/seen: DB error');
    }
    return reply.send({ ok: true });
  });
}

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

    const { bio, mood, avatarColor } = request.body as any;

    const updates: string[] = [];
    const values: any[]    = [];
    let idx = 1;

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
}
