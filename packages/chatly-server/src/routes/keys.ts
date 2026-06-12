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
  // Upload (or refresh) the current user's cryptographic identity keys and prekey bundle.
  // Body: { "identity_key": "...", "dh_identity_key": "...", "signed_prekey": "...", "prekey_signature": "..." }
  fastify.post('/upload', async (request, reply) => {
    const user = verifyToken(request.headers.authorization);
    if (!user) return reply.code(401).send({ error: 'Unauthorized' });

    const { identity_key, dh_identity_key, signed_prekey, prekey_signature } = request.body as any;

    if (!identity_key || !dh_identity_key || !signed_prekey || !prekey_signature) {
      return reply.code(400).send({ error: 'All bundle fields are required: identity_key, dh_identity_key, signed_prekey, prekey_signature' });
    }

    try {
      // Upsert the public keys
      await pool.query(
        `INSERT INTO public_keys (user_id, identity_key, dh_identity_key, signed_prekey, prekey_signature, updated_at)
         VALUES ($1, $2, $3, $4, $5, NOW())
         ON CONFLICT (user_id)
         DO UPDATE SET identity_key = $2, dh_identity_key = $3, signed_prekey = $4, prekey_signature = $5, updated_at = NOW()`,
        [user.userId, identity_key, dh_identity_key, signed_prekey, prekey_signature]
      );

      return reply.send({ success: true });
    } catch (err: any) {
      fastify.log.error(err, 'POST /keys/upload: DB error');
      return reply.code(500).send({ error: 'Failed to store bundle. Please try again.' });
    }
  });

  // GET /api/keys/:username
  // Fetch the cryptographic prekey bundle for a given username.
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
        `SELECT pk.identity_key, pk.dh_identity_key, pk.signed_prekey, pk.prekey_signature
         FROM public_keys pk
         JOIN users u ON pk.user_id = u.id
         WHERE LOWER(u.username) = $1`,
        [clean]
      );

      if (result.rows.length === 0) {
        return reply.send({ identity_key: null, found: false });
      }

      return reply.send({
        identity_key: result.rows[0].identity_key,
        dh_identity_key: result.rows[0].dh_identity_key,
        signed_prekey: result.rows[0].signed_prekey,
        prekey_signature: result.rows[0].prekey_signature,
        found: true
      });
    } catch (err: any) {
      fastify.log.error(err, 'GET /keys/:username: DB error');
      return reply.code(500).send({ error: 'Failed to retrieve keys. Please try again.' });
    }
  });
}
