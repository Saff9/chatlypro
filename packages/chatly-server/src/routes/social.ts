import { FastifyInstance, FastifyPluginOptions } from 'fastify';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import { pool } from '../db';

const JWT_SECRET = process.env.JWT_SECRET || 'chatly-super-secret-key-change-in-prod';

// ─── In-memory fallback stores ────────────────────────────────────────────────
const inMemoryPulses: any[] = [];
import { inMemoryUsers } from './auth';

function verifyToken(authHeader?: string): { userId: string; username: string } | null {
  if (!authHeader || !authHeader.startsWith('Bearer ')) return null;
  try {
    const decoded = jwt.verify(authHeader.split(' ')[1], JWT_SECRET) as any;
    return { userId: decoded.userId, username: decoded.username };
  } catch {
    return null;
  }
}

export async function pulseRoutes(fastify: FastifyInstance, _options: FastifyPluginOptions) {

  // ── GET /api/pulse — list all active pulses (newest first, max 50) ──────────
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
    } catch {
      // memory fallback
      const cutoff = Date.now() - 7 * 24 * 60 * 60 * 1000;
      const pulses = inMemoryPulses
        .filter(p => p.createdAt > cutoff)
        .sort((a, b) => b.createdAt - a.createdAt)
        .slice(0, 50);
      return reply.send({ pulses });
    }
  });

  // ── POST /api/pulse — create a new anonymous pulse ─────────────────────────
  fastify.post('/', async (request, reply) => {
    const user = verifyToken(request.headers.authorization);
    if (!user) return reply.code(401).send({ error: 'Unauthorized' });

    const { text, topics } = request.body as any;
    if (!text || text.trim().length === 0) {
      return reply.code(400).send({ error: 'Pulse text is required' });
    }
    if (text.length > 200) {
      return reply.code(400).send({ error: 'Pulse text must be under 200 characters' });
    }

    const topicsArray = Array.isArray(topics) ? topics : (topics ? topics.split(' ').map((t: string) => t.trim()).filter(Boolean) : []);
    const newId = crypto.randomUUID();

    try {
      const result = await pool.query(
        `INSERT INTO pulse_posts (id, author_id, text, topics, seen_count, replies_count)
         VALUES ($1, $2, $3, $4, 0, 0)
         RETURNING id, text, topics, seen_count, replies_count, created_at`,
        [newId, user.userId, text.trim(), JSON.stringify(topicsArray)]
      );
      return reply.code(201).send({ pulse: result.rows[0] });
    } catch {
      const pulse = {
        id: newId,
        author_id: user.userId,
        text: text.trim(),
        topics: topicsArray,
        seen_count: 0,
        replies_count: 0,
        createdAt: Date.now(),
      };
      inMemoryPulses.push(pulse);
      return reply.code(201).send({ pulse });
    }
  });

  // ── POST /api/pulse/:id/seen — increment seen count ──────────────────────
  fastify.post('/:id/seen', async (request, reply) => {
    const { id } = request.params as any;
    try {
      await pool.query('UPDATE pulse_posts SET seen_count = seen_count + 1 WHERE id = $1', [id]);
    } catch {
      const p = inMemoryPulses.find(x => x.id === id);
      if (p) p.seen_count = (p.seen_count || 0) + 1;
    }
    return reply.send({ ok: true });
  });
}

export async function userRoutes(fastify: FastifyInstance, _options: FastifyPluginOptions) {

  // ── GET /api/users/search?username=xxx — find users by username ────────────
  fastify.get('/search', async (request, reply) => {
    const user = verifyToken(request.headers.authorization);
    if (!user) return reply.code(401).send({ error: 'Unauthorized' });

    const { username } = request.query as any;
    if (!username || username.trim().length < 2) {
      return reply.code(400).send({ error: 'Username query must be at least 2 characters' });
    }
    const q = username.toLowerCase().trim();

    try {
      const result = await pool.query(
        `SELECT id, username, avatar_color, bio, mood, tier
         FROM users
         WHERE LOWER(username) LIKE $1
           AND id != $2
         LIMIT 20`,
        [`%${q}%`, user.userId]
      );
      return reply.send({ users: result.rows });
    } catch {
      const users = inMemoryUsers
        .filter(u => u.username.toLowerCase().includes(q) && u.id !== user.userId)
        .map(u => ({ id: u.id, username: u.username, avatar_color: u.avatarColor, bio: '', mood: '🎵 Vibing', tier: 'free' }));
      return reply.send({ users });
    }
  });

  // ── GET /api/users/profile — get own profile ────────────────────────────────
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
    } catch {
      const u = inMemoryUsers.find(u => u.id === user.userId);
      if (!u) return reply.code(404).send({ error: 'User not found' });
      return reply.send({ profile: { id: u.id, username: u.username, avatar_color: u.avatarColor, bio: '', mood: '🎵 Vibing', tier: 'free' } });
    }
  });

  // ── PUT /api/users/profile — update bio, mood, avatar ─────────────────────
  fastify.put('/profile', async (request, reply) => {
    const user = verifyToken(request.headers.authorization);
    if (!user) return reply.code(401).send({ error: 'Unauthorized' });

    const { bio, mood, avatarColor, displayName } = request.body as any;

    try {
      const updates: string[] = [];
      const values: any[] = [];
      let idx = 1;

      if (bio !== undefined) { updates.push(`bio = $${idx++}`); values.push(bio.slice(0, 100)); }
      if (mood !== undefined) { updates.push(`mood = $${idx++}`); values.push(mood.slice(0, 50)); }
      if (avatarColor !== undefined) { updates.push(`avatar_color = $${idx++}`); values.push(avatarColor); }

      if (updates.length === 0) return reply.code(400).send({ error: 'No fields to update' });

      values.push(user.userId);
      await pool.query(
        `UPDATE users SET ${updates.join(', ')} WHERE id = $${idx}`,
        values
      );
      return reply.send({ success: true });
    } catch {
      const u = inMemoryUsers.find(u => u.id === user.userId);
      if (u) {
        if (bio !== undefined) u.bio = bio;
        if (mood !== undefined) u.mood = mood;
        if (avatarColor !== undefined) u.avatarColor = avatarColor;
      }
      return reply.send({ success: true, note: 'Saved in memory fallback' });
    }
  });
}
