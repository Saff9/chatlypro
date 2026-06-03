import { FastifyInstance, FastifyPluginOptions } from 'fastify';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import { pool } from '../db';
import { sendEmail } from '../services/mail';

// ─── Secrets ──────────────────────────────────────────────────────────────────
const JWT_SECRET = process.env.JWT_SECRET!;
const NODE_ENV   = process.env.NODE_ENV || 'development';

// EMAIL_ENCRYPTION_KEY must be exactly 32 bytes for AES-256-CBC
const RAW_EMAIL_KEY = process.env.EMAIL_ENCRYPTION_KEY || 'chatly-default-key-DO-NOT-USE!!';
const EMAIL_ENCRYPTION_KEY = Buffer.from(RAW_EMAIL_KEY.padEnd(32, '0').slice(0, 32));

// ─── Email Encryption (AES-256-CBC) ───────────────────────────────────────────
function encryptEmail(email: string): string {
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv('aes-256-cbc', EMAIL_ENCRYPTION_KEY, iv);
  let enc = cipher.update(email.toLowerCase().trim(), 'utf8', 'hex');
  enc += cipher.final('hex');
  return iv.toString('hex') + ':' + enc;
}

// Hash email deterministically so we can look it up without decrypting everything
function hashEmail(email: string): string {
  return crypto.createHash('sha256').update(email.toLowerCase().trim()).digest('hex');
}

// ─── Input Validation ─────────────────────────────────────────────────────────
const EMAIL_REGEX    = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const USERNAME_REGEX = /^[a-zA-Z0-9_-]+$/;

const DISPOSABLE_DOMAINS = new Set([
  'mailinator.com','10minutemail.com','tempmail.com','guerrillamail.com','yopmail.com',
  'dispostable.com','getairmail.com','sharklasers.com','guerrillamail.net','guerrillamail.org',
  'guerrillamail.biz','spam4.me','grr.la','pokemail.net','maildrop.cc','temp-mail.org',
  'fakeinbox.com','throwawaymail.com','mailnesia.com','mailcatch.com','burnermicro.com',
  'tempmailaddress.com','trashmail.com','mailnull.com','spamgourmet.com',
]);

function isDisposableEmail(email: string): boolean {
  const domain = email.split('@')[1]?.toLowerCase().trim();
  if (!domain) return true;
  if (DISPOSABLE_DOMAINS.has(domain)) return true;
  if (domain.endsWith('.temp') || domain.endsWith('.tmp')) return true;
  if (domain.startsWith('temp') || domain.startsWith('disposable')) return true;
  return false;
}

// ─── JWT Helper ───────────────────────────────────────────────────────────────
export function signToken(payload: object, expiresIn: string = '7d'): string {
  return jwt.sign(payload, JWT_SECRET, { expiresIn } as jwt.SignOptions);
}

export function verifyToken(authHeader?: string): { userId: string; username: string; emailVerified?: boolean } | null {
  if (!authHeader?.startsWith('Bearer ')) return null;
  try {
    return jwt.verify(authHeader.split(' ')[1], JWT_SECRET) as any;
  } catch {
    return null;
  }
}

// ─── Rate Limiter (per IP, in-memory) ─────────────────────────────────────────
// Uses a sliding window. Trusts X-Forwarded-For from Render's proxy.
const ipRequestHistory = new Map<string, number[]>();

function getClientIp(request: any): string {
  const forwarded = request.headers['x-forwarded-for'];
  if (forwarded) {
    const first = forwarded.split(',')[0].trim();
    if (first) return first;
  }
  return request.ip || 'unknown';
}

function checkRateLimit(ip: string, maxRequests = 15, windowMs = 60_000): boolean {
  const now = Date.now();
  let timestamps = ipRequestHistory.get(ip) || [];
  timestamps = timestamps.filter(t => now - t < windowMs);
  if (timestamps.length >= maxRequests) return false;
  timestamps.push(now);
  ipRequestHistory.set(ip, timestamps);
  return true;
}

// Clean up old rate-limit entries every 5 minutes to prevent memory leaks
setInterval(() => {
  const cutoff = Date.now() - 60_000;
  for (const [ip, timestamps] of ipRequestHistory) {
    const fresh = timestamps.filter(t => t > cutoff);
    if (fresh.length === 0) ipRequestHistory.delete(ip);
    else ipRequestHistory.set(ip, fresh);
  }
}, 300_000);

// ─── OTP helper ───────────────────────────────────────────────────────────────
function generateOtp(): string {
  return crypto.randomInt(100_000, 1_000_000).toString();
}

// ─── Auth Routes ──────────────────────────────────────────────────────────────
export async function authRoutes(fastify: FastifyInstance, _options: FastifyPluginOptions) {

  // POST /api/auth/register
  fastify.post('/register', async (request, reply) => {
    if (!checkRateLimit(getClientIp(request))) {
      return reply.code(429).send({ error: 'Too many requests. Please wait a minute.' });
    }

    const { email, password, username, avatarColor } = request.body as any;

    // Required fields
    if (!email || !password || !username) {
      return reply.code(400).send({ error: 'email, password and username are required' });
    }

    // Username validation: 3–30 chars, alphanumeric/dash/underscore
    const cleanUsername = username.toLowerCase().trim();
    if (cleanUsername.length < 3 || cleanUsername.length > 30) {
      return reply.code(400).send({ error: 'Username must be 3–30 characters' });
    }
    if (!USERNAME_REGEX.test(cleanUsername)) {
      return reply.code(400).send({ error: 'Username may only contain letters, numbers, dashes and underscores' });
    }

    // Email validation
    const cleanEmail = email.toLowerCase().trim();
    if (!EMAIL_REGEX.test(cleanEmail)) {
      return reply.code(400).send({ error: 'Invalid email format' });
    }
    if (isDisposableEmail(cleanEmail)) {
      return reply.code(400).send({ error: 'Disposable or temporary email addresses are not allowed' });
    }

    // Password strength
    if (password.length < 8) {
      return reply.code(400).send({ error: 'Password must be at least 8 characters' });
    }

    const emailHash      = hashEmail(cleanEmail);
    const emailEncrypted = encryptEmail(cleanEmail);
    const passwordHash   = await bcrypt.hash(password, 12);
    const otp            = generateOtp();
    const otpExpiry      = new Date(Date.now() + 15 * 60 * 1000);

    try {
      const result = await pool.query(
        `INSERT INTO users (email_hash, email_encrypted, password_hash, username, avatar_color, email_verified)
         VALUES ($1, $2, $3, $4, $5, FALSE) RETURNING id`,
        [emailHash, emailEncrypted, passwordHash, cleanUsername, avatarColor || '#6366F1']
      );
      const userId = result.rows[0].id;

      await pool.query(
        `INSERT INTO email_verifications (email, code, expires_at)
         VALUES ($1, $2, $3)
         ON CONFLICT (email) DO UPDATE SET code = $2, expires_at = $3`,
        [emailHash, otp, otpExpiry]
      );

      await sendEmail({
        to: cleanEmail,
        subject: 'Verify your Chatly account',
        text: `Welcome to Chatly!\n\nYour verification code is: ${otp}\n\nIt expires in 15 minutes.`,
      });

      const token = signToken({ userId, username: cleanUsername, emailVerified: false });
      return reply.code(201).send({ token, userId, username: cleanUsername, emailVerified: false });
    } catch (err: any) {
      if (err.code === '23505') {
        // Unique constraint: email or username already taken
        return reply.code(400).send({ error: 'Email or username is already taken' });
      }
      fastify.log.error(err, 'register: DB error');
      return reply.code(500).send({ error: 'Registration failed. Please try again.' });
    }
  });

  // POST /api/auth/verify-email
  fastify.post('/verify-email', async (request, reply) => {
    if (!checkRateLimit(getClientIp(request), 10)) {
      return reply.code(429).send({ error: 'Too many requests. Please wait.' });
    }

    const { email, code } = request.body as any;
    if (!email || !code) {
      return reply.code(400).send({ error: 'email and code are required' });
    }

    const emailHash = hashEmail(email);

    try {
      const verifyRes = await pool.query(
        `SELECT 1 FROM email_verifications
         WHERE email = $1 AND code = $2 AND expires_at > NOW()`,
        [emailHash, String(code)]
      );

      if (verifyRes.rows.length === 0) {
        return reply.code(400).send({ error: 'Invalid or expired verification code' });
      }

      // Mark verified and remove OTP atomically
      await pool.query('UPDATE users SET email_verified = TRUE WHERE email_hash = $1', [emailHash]);
      await pool.query('DELETE FROM email_verifications WHERE email = $1', [emailHash]);

      const userRes = await pool.query(
        'SELECT id, username FROM users WHERE email_hash = $1',
        [emailHash]
      );
      if (userRes.rows.length === 0) {
        return reply.code(404).send({ error: 'User not found' });
      }
      const user = userRes.rows[0];
      const token = signToken({ userId: user.id, username: user.username, emailVerified: true });
      return reply.send({ token, userId: user.id, username: user.username, emailVerified: true });
    } catch (err: any) {
      fastify.log.error(err, 'verify-email: DB error');
      return reply.code(500).send({ error: 'Verification failed. Please try again.' });
    }
  });

  // POST /api/auth/resend-verification
  fastify.post('/resend-verification', async (request, reply) => {
    if (!checkRateLimit(getClientIp(request), 5)) {
      return reply.code(429).send({ error: 'Too many requests. Please wait.' });
    }

    const { email } = request.body as any;
    if (!email) return reply.code(400).send({ error: 'email is required' });

    const cleanEmail = email.toLowerCase().trim();
    const emailHash  = hashEmail(cleanEmail);
    const otp        = generateOtp();
    const otpExpiry  = new Date(Date.now() + 15 * 60 * 1000);

    try {
      const userRes = await pool.query('SELECT id FROM users WHERE email_hash = $1', [emailHash]);
      if (userRes.rows.length > 0) {
        await pool.query(
          `INSERT INTO email_verifications (email, code, expires_at)
           VALUES ($1, $2, $3)
           ON CONFLICT (email) DO UPDATE SET code = $2, expires_at = $3`,
          [emailHash, otp, otpExpiry]
        );
        await sendEmail({
          to: cleanEmail,
          subject: 'Your Chatly verification code',
          text: `Your verification code is: ${otp}\n\nIt expires in 15 minutes.`,
        });
      }
    } catch (err: any) {
      fastify.log.error(err, 'resend-verification: DB error');
    }

    // Always return success to prevent email enumeration
    return reply.send({ success: true, message: 'If that email exists, a code has been sent.' });
  });

  // POST /api/auth/login
  fastify.post('/login', async (request, reply) => {
    if (!checkRateLimit(getClientIp(request), 10)) {
      return reply.code(429).send({ error: 'Too many requests. Please wait a minute.' });
    }

    const { email, password } = request.body as any;
    if (!email || !password) {
      return reply.code(400).send({ error: 'email and password are required' });
    }

    const emailHash = hashEmail(email);

    try {
      // Only look up by email_hash — email_encrypted is NOT deterministic (random IV per call)
      const result = await pool.query(
        `SELECT id, username, password_hash, email_verified, two_factor_enabled
         FROM users WHERE email_hash = $1`,
        [emailHash]
      );

      if (result.rows.length === 0) {
        // Constant-time response to prevent timing attacks / user enumeration
        await bcrypt.compare(password, '$2a$12$invalidhashfortimingnormalizati');
        return reply.code(401).send({ error: 'Invalid email or password' });
      }

      const user = result.rows[0];

      if (!user.password_hash) {
        return reply.code(401).send({ error: 'Invalid email or password' });
      }

      const isValid = await bcrypt.compare(password, user.password_hash);
      if (!isValid) {
        return reply.code(401).send({ error: 'Invalid email or password' });
      }

      // Email must be verified before login
      if (!user.email_verified) {
        const otp       = generateOtp();
        const otpExpiry = new Date(Date.now() + 15 * 60 * 1000);
        await pool.query(
          `INSERT INTO email_verifications (email, code, expires_at)
           VALUES ($1, $2, $3)
           ON CONFLICT (email) DO UPDATE SET code = $2, expires_at = $3`,
          [emailHash, otp, otpExpiry]
        );
        await sendEmail({
          to: email,
          subject: 'Verify your Chatly account',
          text: `Your verification code is: ${otp}\n\nIt expires in 15 minutes.`,
        });
        return reply.code(403).send({ emailVerified: false, error: 'Email not verified. A new code has been sent.' });
      }

      // 2FA flow
      if (user.two_factor_enabled) {
        const otp       = generateOtp();
        const otpExpiry = new Date(Date.now() + 5 * 60 * 1000);
        await pool.query(
          `INSERT INTO two_factor_temp (user_id, code, expires_at)
           VALUES ($1, $2, $3)
           ON CONFLICT (user_id) DO UPDATE SET code = $2, expires_at = $3`,
          [user.id, otp, otpExpiry]
        );
        await sendEmail({
          to: email,
          subject: 'Chatly login verification code',
          text: `Your 2-step login code is: ${otp}\n\nIt expires in 5 minutes.`,
        });
        const tempToken = signToken({ userId: user.id, username: user.username, isTemp2FA: true }, '5m');
        return reply.send({ twoFactorRequired: true, tempToken });
      }

      const token = signToken({ userId: user.id, username: user.username, emailVerified: true });
      return reply.send({ token, userId: user.id, username: user.username, emailVerified: true });
    } catch (err: any) {
      fastify.log.error(err, 'login: DB error');
      return reply.code(500).send({ error: 'Login failed. Please try again.' });
    }
  });

  // POST /api/auth/verify-2fa
  fastify.post('/verify-2fa', async (request, reply) => {
    if (!checkRateLimit(getClientIp(request), 10)) {
      return reply.code(429).send({ error: 'Too many requests. Please wait.' });
    }

    const { tempToken, code } = request.body as any;
    if (!tempToken || !code) {
      return reply.code(400).send({ error: 'tempToken and code are required' });
    }

    let userId: string;
    let username: string;
    try {
      const decoded = jwt.verify(tempToken, JWT_SECRET) as any;
      if (!decoded.isTemp2FA) {
        return reply.code(401).send({ error: 'Invalid token type' });
      }
      userId   = decoded.userId;
      username = decoded.username;
    } catch {
      return reply.code(401).send({ error: 'Invalid or expired 2FA token' });
    }

    try {
      const otpRes = await pool.query(
        `SELECT 1 FROM two_factor_temp
         WHERE user_id = $1 AND code = $2 AND expires_at > NOW()`,
        [userId, String(code)]
      );
      if (otpRes.rows.length === 0) {
        return reply.code(400).send({ error: 'Invalid or expired 2FA code' });
      }

      await pool.query('DELETE FROM two_factor_temp WHERE user_id = $1', [userId]);
      const token = signToken({ userId, username, emailVerified: true });
      return reply.send({ token, userId, username, emailVerified: true });
    } catch (err: any) {
      fastify.log.error(err, 'verify-2fa: DB error');
      return reply.code(500).send({ error: '2FA verification failed. Please try again.' });
    }
  });

  // POST /api/auth/toggle-2fa  (requires valid Bearer token)
  fastify.post('/toggle-2fa', async (request, reply) => {
    const user = verifyToken(request.headers.authorization);
    if (!user) return reply.code(401).send({ error: 'Unauthorized' });

    const { enabled } = request.body as any;
    if (typeof enabled !== 'boolean') {
      return reply.code(400).send({ error: 'enabled must be a boolean' });
    }

    try {
      const result = await pool.query(
        'UPDATE users SET two_factor_enabled = $1 WHERE id = $2 RETURNING id',
        [enabled, user.userId]
      );
      if (result.rowCount === 0) return reply.code(404).send({ error: 'User not found' });
      return reply.send({ success: true, twoFactorEnabled: enabled });
    } catch (err: any) {
      fastify.log.error(err, 'toggle-2fa: DB error');
      return reply.code(500).send({ error: 'Failed to update 2FA setting' });
    }
  });

  // GET /api/auth/username-check?username=xxx
  fastify.get('/username-check', async (request, reply) => {
    if (!checkRateLimit(getClientIp(request), 30)) {
      return reply.code(429).send({ error: 'Too many requests' });
    }

    const { username } = request.query as any;
    if (!username) return reply.code(400).send({ error: 'username is required' });

    const clean = username.toLowerCase().trim();
    if (clean.length < 3 || clean.length > 30 || !USERNAME_REGEX.test(clean)) {
      return reply.send({ available: false, reason: 'invalid_format' });
    }

    try {
      const result = await pool.query('SELECT 1 FROM users WHERE username = $1', [clean]);
      return reply.send({ available: result.rows.length === 0 });
    } catch (err: any) {
      fastify.log.error(err, 'username-check: DB error');
      return reply.code(500).send({ error: 'Check failed. Please try again.' });
    }
  });

  // POST /api/auth/push-token  (requires valid Bearer token)
  fastify.post('/push-token', async (request, reply) => {
    const user = verifyToken(request.headers.authorization);
    if (!user) return reply.code(401).send({ error: 'Unauthorized' });

    const { pushToken } = request.body as any;
    if (!pushToken || typeof pushToken !== 'string' || pushToken.length > 512) {
      return reply.code(400).send({ error: 'Valid pushToken is required' });
    }

    try {
      const result = await pool.query(
        'UPDATE users SET push_token = $1 WHERE id = $2 RETURNING id',
        [pushToken, user.userId]
      );
      if (result.rowCount === 0) return reply.code(404).send({ error: 'User not found' });
      return reply.send({ success: true });
    } catch (err: any) {
      fastify.log.error(err, 'push-token: DB error');
      return reply.code(500).send({ error: 'Failed to update push token' });
    }
  });
}
