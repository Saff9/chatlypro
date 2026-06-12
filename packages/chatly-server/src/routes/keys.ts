import { FastifyInstance, FastifyPluginOptions } from 'fastify';
import { pool } from '../db';
import { verifyToken } from './auth';

// ─── Key Routes ───────────────────────────────────────────────────────────────
// These routes enable real E2E encrypted key exchange between users.
// The public_keys table already exists in the schema.
// Without these routes, the Flutter app falls back to fake random keys,
// making E2EE non-functional between different users.
export async function keysRoutes(fastify: FastifyInstance, _options: FastifyPluginOptions) {

  // POST /api/keys/upload
  // Upload (or refresh) the current user's X25519 public identity key.
  // Body: { "identity_key": "<base64-encoded X25519 public key>" }
  // Called by the Flutter client after registration or login.
  fastify.post('/upload', async (request, reply) => {
    const user = verifyToken(request.headers.authorization);
    if (!user) return reply.code(401).send({ error: 'Unauthorized' });

    const { identity_key } = request.body as any;

    if (!identity_key || typeof identity_key !== 'string') {
      return reply.code(400).send({ error: 'identity_key is required and must be a base64 string' });
    }

    // Basic length sanity check for X25519 public key (32 bytes = 44 base64 chars)
    if (identity_key.length < 40 || identity_key.length > 100) {
      return reply.code(400).send({ error: 'identity_key has invalid length for an X25519 public key' });
    }

    try {
      // Upsert: insert or update if already exists
      await pool.query(
        `INSERT INTO public_keys (user_id, identity_key, signed_prekey, prekey_signature, updated_at)
         VALUES ($1, $2, '', '', NOW())
         ON CONFLICT (user_id)
         DO UPDATE SET identity_key = $2, updated_at = NOW()`,
        [user.userId, identity_key]
      );

      return reply.send({ success: true });
    } catch (err: any) {
      fastify.log.error(err, 'POST /keys/upload: DB error');
      return reply.code(500).send({ error: 'Failed to store key. Please try again.' });
    }
  });

  // GET /api/keys/:username
  // Fetch the X25519 public identity key for a given username.
  // Required by the Flutter client before starting an encrypted chat.
  // Returns null identity_key if the user has not uploaded a key yet.
  fastify.get('/:username', async (request, reply) => {
    const caller = verifyToken(request.headers.authorization);
    if (!caller) return reply.code(401).send({ error: 'Unauthorized' });

    const { username } = request.params as any;
    if (!username || typeof username !== 'string') {
      return reply.code(400).send({ error: 'username is required' });
    }

    const clean = username.toLowerCase().trim();
    if (clean.length < 3 || clean.length > 30) {
      return reply.code(400).send({ error: 'Invalid username' });
    }

    try {
      const result = await pool.query(
        `SELECT pk.identity_key
         FROM public_keys pk
         JOIN users u ON pk.user_id = u.id
         WHERE LOWER(u.username) = $1`,
        [clean]
      );

      if (result.rows.length === 0) {
        // User exists but has not uploaded a key yet — client should wait
        return reply.send({ identity_key: null, found: false });
      }

      return reply.send({ identity_key: result.rows[0].identity_key, found: true });
    } catch (err: any) {
      fastify.log.error(err, 'GET /keys/:username: DB error');
      return reply.code(500).send({ error: 'Failed to retrieve key. Please try again.' });
    }
  });
}
