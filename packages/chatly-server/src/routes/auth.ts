import { FastifyInstance, FastifyPluginOptions } from 'fastify';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import { pool } from '../db';
import { sendEmail } from '../services/mail';
import { redisClient } from '../db/redis';
import { MemoryFallback } from '../db/redis';

const JWT_SECRET = process.env.JWT_SECRET || 'chatly-super-secret-key-change-in-prod';
const NODE_ENV = process.env.NODE_ENV || 'development';

if (NODE_ENV === 'production' && JWT_SECRET === 'chatly-super-secret-key-change-in-prod') {
  console.error('[FATAL] JWT_SECRET must be set to a strong random value in production. Refusing to start.');
  process.exit(1);
}

// AES-256-CBC email encryption
const EMAIL_ENCRYPTION_KEY = process.env.EMAIL_ENCRYPTION_KEY || 'default-secret-key-32-chars-long!'; // 32 characters

function encryptEmail(email: string): string {
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv('aes-256-cbc', Buffer.from(EMAIL_ENCRYPTION_KEY.substring(0, 32)), iv);
  let encrypted = cipher.update(email.toLowerCase().trim(), 'utf8', 'hex');
  encrypted += cipher.final('hex');
  return iv.toString('hex') + ':' + encrypted;
}

function decryptEmail(encryptedData: string): string {
  try {
    const parts = encryptedData.split(':');
    if (parts.length !== 2) return encryptedData;
    const iv = Buffer.from(parts[0], 'hex');
    const encryptedText = Buffer.from(parts[1], 'hex');
    const decipher = crypto.createDecipheriv('aes-256-cbc', Buffer.from(EMAIL_ENCRYPTION_KEY.substring(0, 32)), iv);
    let decrypted = decipher.update(encryptedText);
    decrypted = Buffer.concat([decrypted, decipher.final()]);
    return decrypted.toString('utf8');
  } catch (e) {
    return encryptedData; // fallback
  }
}

function hashEmail(email: string): string {
  return crypto.createHash('sha256').update(email.toLowerCase().trim()).digest('hex');
}

// Simple in-memory user fallback for testing without DB setup
export interface InMemoryUser {
  id: string;
  emailHash: string;
  emailEncrypted: string;
  passwordHash: string;
  username: string;
  avatarColor: string;
  emailVerified: boolean;
  twoFactorEnabled: boolean;
  bio?: string;
  mood?: string;
}
export const inMemoryUsers: InMemoryUser[] = [];
export const inMemoryPushTokens = new Map<string, string>();

// Temp Mail Providers Blocklist
const DISPOSABLE_EMAIL_DOMAINS = [
  'mailinator.com', '10minutemail.com', 'tempmail.com', 'guerrillamail.com', 
  'yopmail.com', 'dispostable.com', 'getairmail.com', 'sharklasers.com',
  'guerrillamailblock.com', 'guerrillamail.net', 'guerrillamail.org',
  'guerrillamail.biz', 'spam4.me', 'grr.la', 'pokemail.net',
  'maildrop.cc', 'temp-mail.org', 'fakeinbox.com', 'throwawaymail.com',
  'mailnesia.com', 'mailcatch.com', 'burnermicro.com', 'tempmailaddress.com'
];

function isDisposableEmail(email: string): boolean {
  const domain = email.split('@')[1]?.toLowerCase().trim();
  if (!domain) return true;
  return DISPOSABLE_EMAIL_DOMAINS.some(d => domain === d || domain.endsWith('.' + d)) || 
         domain.endsWith('.temp') || 
         domain.endsWith('.tmp') ||
         domain.startsWith('temp') ||
         domain.startsWith('disposable');
}

// In-Memory IP Rate Limiter
interface RateLimitData {
  timestamps: number[];
}
const ipRequestHistory = new Map<string, RateLimitData>();

async function checkRateLimit(ip: string): Promise<boolean> {
  const now = Date.now();
  const limitWindow = 60000; // 1 minute
  const maxRequests = 15; // slightly increased to cover app usage

  if (!(redisClient instanceof MemoryFallback)) {
    const key = `ratelimit:${ip}`;
    try {
      const current = await redisClient.get(key);
      if (current && parseInt(current, 10) >= maxRequests) {
        return false;
      }
      const multi = (redisClient as any).multi();
      multi.incr(key);
      multi.expire(key, 60);
      await multi.exec();
      return true;
    } catch (err) {
      console.error('Redis rate limit check failed, falling back to memory:', err);
    }
  }

  // Memory fallback
  if (!ipRequestHistory.has(ip)) {
    ipRequestHistory.set(ip, { timestamps: [now] });
    return true;
  }

  const record = ipRequestHistory.get(ip)!;
  record.timestamps = record.timestamps.filter(t => now - t < limitWindow);

  if (record.timestamps.length >= maxRequests) {
    return false;
  }

  record.timestamps.push(now);
  return true;
}

// Memory fallbacks for codes
interface OtpData {
  code: string;
  expiresAt: number;
}
const inMemoryEmailVerifications = new Map<string, OtpData>();
const inMemoryTwoFactorTemp = new Map<string, OtpData>();

export async function authRoutes(fastify: FastifyInstance, options: FastifyPluginOptions) {
  
  // Register Endpoint
  fastify.post('/register', async (request, reply) => {
    const ip = request.ip;
    if (!await checkRateLimit(ip)) {
      return reply.code(429).send({ error: 'Too many requests. Please wait a minute.' });
    }

    const { email, password, username, avatarColor } = request.body as any;

    if (!email || !password || !username) {
      return reply.code(400).send({ error: 'Missing required parameters' });
    }

    // Input Validation
    const cleanUsername = username.toLowerCase().trim();
    const alphanumericRegex = /^[a-zA-Z0-9_-]+$/;
    if (!alphanumericRegex.test(cleanUsername)) {
      return reply.code(400).send({ error: 'Username must be alphanumeric (dashes/underscores allowed)' });
    }

    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
      return reply.code(400).send({ error: 'Invalid email format' });
    }

    if (password.length < 8) {
      return reply.code(400).send({ error: 'Password must be at least 8 characters long' });
    }

    // Disposable/Temp Mail Blocker
    if (isDisposableEmail(email)) {
      return reply.code(400).send({ error: 'Registration blocked: Temporary or disposable email accounts are not permitted.' });
    }

    const passwordHash = await bcrypt.hash(password, 10);
    const emailHash = hashEmail(email);
    const encryptedEmail = encryptEmail(email);
    const verificationCode = crypto.randomInt(100000, 1000000).toString();
    const verificationExpiry = new Date(Date.now() + 15 * 60 * 1000); // 15 mins

    try {
      // Attempt PostgreSQL insertion
      const result = await pool.query(
        `INSERT INTO users (email_hash, email_encrypted, password_hash, username, avatar_color, email_verified) 
         VALUES ($1, $2, $3, $4, $5, FALSE) RETURNING id`,
        [emailHash, encryptedEmail, passwordHash, cleanUsername, avatarColor || '#6366F1']
      );
      
      const newUserId = result.rows[0].id;

      // Save verification code to DB
      await pool.query(
        `INSERT INTO email_verifications (email, code, expires_at) 
         VALUES ($1, $2, $3) 
         ON CONFLICT (email) DO UPDATE SET code = $2, expires_at = $3`,
        [emailHash, verificationCode, verificationExpiry]
      );

      // Dispatch verification code
      await sendEmail({
        to: email,
        subject: 'Verify your Chatly Registration',
        text: `Welcome to Chatly! Your registration verification code is: ${verificationCode}. It expires in 15 minutes.`
      });

      const token = jwt.sign({ userId: newUserId, username: cleanUsername, emailVerified: false }, JWT_SECRET, { expiresIn: '7d' });
      return reply.code(201).send({ token, userId: newUserId, username: cleanUsername, emailVerified: false });
    } catch (err: any) {
      console.warn('Postgres connection failed or unique constraint triggered. Trying in-memory fallback:', err.message);
      
      // In-Memory Fallback
      const userExists = inMemoryUsers.some(u => u.emailHash === emailHash || u.username === cleanUsername);
      if (userExists) {
        return reply.code(400).send({ error: 'User with this email or username already exists' });
      }

      const newId = crypto.randomUUID ? crypto.randomUUID() : Math.random().toString(36).substring(2);
      const newUser: InMemoryUser = {
        id: newId,
        emailHash,
        emailEncrypted: encryptedEmail,
        passwordHash,
        username: cleanUsername,
        avatarColor: avatarColor || '#6366F1',
        emailVerified: false,
        twoFactorEnabled: false
      };
      inMemoryUsers.push(newUser);

      // Save code to memory
      inMemoryEmailVerifications.set(emailHash, {
        code: verificationCode,
        expiresAt: Date.now() + 15 * 60 * 1000
      });

      await sendEmail({
        to: email,
        subject: 'Verify your Chatly Registration',
        text: `Welcome to Chatly! Your registration verification code is: ${verificationCode}. It expires in 15 minutes.`
      });
      
      const token = jwt.sign({ userId: newId, username: cleanUsername, emailVerified: false }, JWT_SECRET, { expiresIn: '7d' });
      return reply.code(201).send({ token, userId: newId, username: cleanUsername, emailVerified: false, note: 'Registered in Memory' });
    }
  });

  // Verify Email Endpoint
  fastify.post('/verify-email', async (request, reply) => {
    const ip = request.ip;
    if (!await checkRateLimit(ip)) {
      return reply.code(429).send({ error: 'Too many requests. Please wait a minute.' });
    }

    const { email, code } = request.body as any;
    if (!email || !code) {
      return reply.code(400).send({ error: 'Missing email or verification code' });
    }

    const emailHash = hashEmail(email);

    try {
      // Postgres verification
      const verifyRes = await pool.query(
        'SELECT code, expires_at FROM email_verifications WHERE email = $1 AND code = $2 AND expires_at > NOW()',
        [emailHash, code]
      );

      if (verifyRes.rows.length > 0) {
        // Update user status
        await pool.query('UPDATE users SET email_verified = TRUE WHERE email_hash = $1 OR email_encrypted = $2', [emailHash, email]);
        await pool.query('DELETE FROM email_verifications WHERE email = $1', [emailHash]);

        const userRes = await pool.query('SELECT id, username FROM users WHERE email_hash = $1 OR email_encrypted = $2', [emailHash, email]);
        const user = userRes.rows[0];

        const token = jwt.sign({ userId: user.id, username: user.username, emailVerified: true }, JWT_SECRET, { expiresIn: '7d' });
        return reply.send({ token, userId: user.id, username: user.username, emailVerified: true });
      }
    } catch (err: any) {
      console.warn('Postgres verification failed, checking memory:', err.message);
    }

    // Memory verification fallback
    const otpRecord = inMemoryEmailVerifications.get(emailHash);
    if (otpRecord && otpRecord.code === code && Date.now() < otpRecord.expiresAt) {
      const memoryUser = inMemoryUsers.find(u => u.emailHash === emailHash);
      if (memoryUser) {
        memoryUser.emailVerified = true;
        inMemoryEmailVerifications.delete(emailHash);

        const token = jwt.sign({ userId: memoryUser.id, username: memoryUser.username, emailVerified: true }, JWT_SECRET, { expiresIn: '7d' });
        return reply.send({ token, userId: memoryUser.id, username: memoryUser.username, emailVerified: true });
      }
    }

    return reply.code(400).send({ error: 'Invalid or expired verification code' });
  });

  // Resend Email Verification Endpoint
  fastify.post('/resend-verification', async (request, reply) => {
    const ip = request.ip;
    if (!await checkRateLimit(ip)) {
      return reply.code(429).send({ error: 'Too many requests. Please wait a minute.' });
    }

    const { email } = request.body as any;
    if (!email) {
      return reply.code(400).send({ error: 'Missing email' });
    }

    const emailHash = hashEmail(email);
    const verificationCode = crypto.randomInt(100000, 1000000).toString();
    const verificationExpiry = new Date(Date.now() + 15 * 60 * 1000);

    try {
      const userRes = await pool.query('SELECT id FROM users WHERE email_hash = $1 OR email_encrypted = $2', [emailHash, email]);
      if (userRes.rows.length > 0) {
        await pool.query(
          `INSERT INTO email_verifications (email, code, expires_at) 
           VALUES ($1, $2, $3) 
           ON CONFLICT (email) DO UPDATE SET code = $2, expires_at = $3`,
          [emailHash, verificationCode, verificationExpiry]
        );
        await sendEmail({
          to: email,
          subject: 'Verify your Chatly Email',
          text: `Your email verification code is: ${verificationCode}. It expires in 15 minutes.`
        });
      }
    } catch (err: any) {
      console.warn('Postgres resend failed, checking memory:', err.message);
    }

    const memoryUser = inMemoryUsers.find(u => u.emailHash === emailHash);
    if (memoryUser) {
      inMemoryEmailVerifications.set(emailHash, {
        code: verificationCode,
        expiresAt: Date.now() + 15 * 60 * 1000
      });
      await sendEmail({
        to: email,
        subject: 'Verify your Chatly Email',
        text: `Your email verification code is: ${verificationCode}. It expires in 15 minutes.`
      });
    }

    // Generic response to prevent user enumeration
    return reply.send({ success: true, message: 'Verification code sent if email exists.' });
  });

  // Login Endpoint
  fastify.post('/login', async (request, reply) => {
    const ip = request.ip;
    if (!await checkRateLimit(ip)) {
      return reply.code(429).send({ error: 'Too many requests. Please wait a minute.' });
    }

    const { email, password } = request.body as any;

    if (!email || !password) {
      return reply.code(400).send({ error: 'Missing email or password' });
    }

    const emailHash = hashEmail(email);

    try {
      // Postgres check with explicit column selection
      const result = await pool.query(
        'SELECT id, username, password_hash, email_verified, two_factor_enabled FROM users WHERE email_hash = $1 OR email_encrypted = $2',
        [emailHash, email]
      );
      
      if (result.rows.length > 0) {
        const user = result.rows[0];

        // Explicit empty password hash check to prevent BCrypt compare bypass
        if (!user.password_hash) {
          return reply.code(401).send({ error: 'Invalid email or password' });
        }

        // Verify password
        const isPasswordValid = await bcrypt.compare(password, user.password_hash);
        if (!isPasswordValid) {
          return reply.code(401).send({ error: 'Invalid email or password' });
        }

        // Check if email is verified
        if (!user.email_verified) {
          const verificationCode = crypto.randomInt(100000, 1000000).toString();
          const verificationExpiry = new Date(Date.now() + 15 * 60 * 1000);
          await pool.query(
            `INSERT INTO email_verifications (email, code, expires_at) 
             VALUES ($1, $2, $3) 
             ON CONFLICT (email) DO UPDATE SET code = $2, expires_at = $3`,
            [emailHash, verificationCode, verificationExpiry]
          );
          await sendEmail({
            to: email,
            subject: 'Verify your Chatly Email',
            text: `Your email verification code is: ${verificationCode}. It expires in 15 minutes.`
          });
          return reply.code(403).send({ emailVerified: false, email, error: 'Email not verified. Verification code resent.' });
        }

        // Check if 2-Step Verification is active
        if (user.two_factor_enabled) {
          const otpCode = crypto.randomInt(100000, 1000000).toString();
          const otpExpiry = new Date(Date.now() + 5 * 60 * 1000); // 5 mins
          await pool.query(
            `INSERT INTO two_factor_temp (user_id, code, expires_at) 
             VALUES ($1, $2, $3) 
             ON CONFLICT (user_id) DO UPDATE SET code = $2, expires_at = $3`,
            [user.id, otpCode, otpExpiry]
          );
          await sendEmail({
            to: email,
            subject: 'Chatly Two-Step Verification Login',
            text: `Your 2-Step login code is: ${otpCode}. It expires in 5 minutes.`
          });

          const tempToken = jwt.sign({ userId: user.id, username: user.username, isTemp2FA: true }, JWT_SECRET, { expiresIn: '5m' });
          return reply.send({ twoFactorRequired: true, tempToken, email });
        }

        const token = jwt.sign({ userId: user.id, username: user.username, emailVerified: true }, JWT_SECRET, { expiresIn: '7d' });
        return reply.send({ token, userId: user.id, username: user.username, emailVerified: true });
      }
    } catch (err: any) {
      console.warn('Postgres lookup error, falling back to memory search:', err.message);
    }

    // In-Memory Check
    const memoryUser = inMemoryUsers.find(u => u.emailHash === emailHash);
    if (memoryUser) {
      const isPasswordValid = await bcrypt.compare(password, memoryUser.passwordHash);
      if (isPasswordValid) {
        if (!memoryUser.emailVerified) {
          const verificationCode = crypto.randomInt(100000, 1000000).toString();
          inMemoryEmailVerifications.set(emailHash, {
            code: verificationCode,
            expiresAt: Date.now() + 15 * 60 * 1000
          });
          await sendEmail({
            to: email,
            subject: 'Verify your Chatly Email',
            text: `Your email verification code is: ${verificationCode}. It expires in 15 minutes.`
          });
          return reply.code(403).send({ emailVerified: false, email, error: 'Email not verified. Verification code resent.' });
        }

        if (memoryUser.twoFactorEnabled) {
          const otpCode = crypto.randomInt(100000, 1000000).toString();
          inMemoryTwoFactorTemp.set(memoryUser.id, {
            code: otpCode,
            expiresAt: Date.now() + 5 * 60 * 1000
          });
          await sendEmail({
            to: email,
            subject: 'Chatly Two-Step Verification Login',
            text: `Your 2-Step login code is: ${otpCode}. It expires in 5 minutes.`
          });

          const tempToken = jwt.sign({ userId: memoryUser.id, username: memoryUser.username, isTemp2FA: true }, JWT_SECRET, { expiresIn: '5m' });
          return reply.send({ twoFactorRequired: true, tempToken, email });
        }

        const token = jwt.sign({ userId: memoryUser.id, username: memoryUser.username, emailVerified: true }, JWT_SECRET, { expiresIn: '7d' });
        return reply.send({ token, userId: memoryUser.id, username: memoryUser.username, emailVerified: true });
      }
    }

    return reply.code(401).send({ error: 'Invalid email or password' });
  });

  // Verify 2-Step Verification Code Endpoint
  fastify.post('/verify-2fa', async (request, reply) => {
    const ip = request.ip;
    if (!await checkRateLimit(ip)) {
      return reply.code(429).send({ error: 'Too many requests. Please wait a minute.' });
    }

    const { tempToken, code } = request.body as any;
    if (!tempToken || !code) {
      return reply.code(400).send({ error: 'Missing tempToken or 2FA code' });
    }

    let userId: string;
    let username: string;
    try {
      const decoded = jwt.verify(tempToken, JWT_SECRET) as { userId: string; username: string; isTemp2FA?: boolean };
      if (!decoded.isTemp2FA) {
        return reply.code(401).send({ error: 'Invalid 2FA authorization token type.' });
      }
      userId = decoded.userId;
      username = decoded.username;
    } catch (err) {
      return reply.code(401).send({ error: 'Invalid or expired 2FA authorization token.' });
    }

    try {
      const otpRes = await pool.query(
        'SELECT code, expires_at FROM two_factor_temp WHERE user_id = $1 AND code = $2 AND expires_at > NOW()',
        [userId, code]
      );
      if (otpRes.rows.length > 0) {
        await pool.query('DELETE FROM two_factor_temp WHERE user_id = $1', [userId]);

        const token = jwt.sign({ userId, username, emailVerified: true }, JWT_SECRET, { expiresIn: '7d' });
        return reply.send({ token, userId, username, emailVerified: true });
      }
    } catch (err: any) {
      console.warn('Postgres 2FA check failed, verifying memory:', err.message);
    }

    const memoryOtp = inMemoryTwoFactorTemp.get(userId);
    if (memoryOtp && memoryOtp.code === code && Date.now() < memoryOtp.expiresAt) {
      inMemoryTwoFactorTemp.delete(userId);

      const token = jwt.sign({ userId, username, emailVerified: true }, JWT_SECRET, { expiresIn: '7d' });
      return reply.send({ token, userId, username, emailVerified: true });
    }

    return reply.code(400).send({ error: 'Invalid or expired 2FA verification code.' });
  });

  // Toggle 2-Step Verification Configuration (Authenticated)
  fastify.post('/toggle-2fa', async (request, reply) => {
    const authHeader = request.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return reply.code(401).send({ error: 'Unauthorized: Missing or invalid authorization' });
    }

    const token = authHeader.split(' ')[1];
    let userId: string;
    try {
      const decoded = jwt.verify(token, JWT_SECRET) as { userId: string };
      userId = decoded.userId;
    } catch (err) {
      return reply.code(401).send({ error: 'Unauthorized: Invalid token' });
    }

    const { enabled } = request.body as any;
    if (enabled === undefined) {
      return reply.code(400).send({ error: 'Missing enabled flag in request body' });
    }

    try {
      const result = await pool.query(
        'UPDATE users SET two_factor_enabled = $1 WHERE id = $2 RETURNING id',
        [enabled, userId]
      );

      if (result.rowCount === 0) {
        // Fallback to memory user
        const memoryUser = inMemoryUsers.find(u => u.id === userId);
        if (memoryUser) {
          memoryUser.twoFactorEnabled = enabled;
          return reply.send({ success: true, twoFactorEnabled: enabled, note: 'Updated 2FA status in memory fallback' });
        }
        return reply.code(404).send({ error: 'User not found' });
      }

      return reply.send({ success: true, twoFactorEnabled: enabled });
    } catch (err: any) {
      console.warn('Failed to update 2FA state in Postgres, trying memory:', err.message);
      
      const memoryUser = inMemoryUsers.find(u => u.id === userId);
      if (memoryUser) {
        memoryUser.twoFactorEnabled = enabled;
        return reply.send({ success: true, twoFactorEnabled: enabled, note: 'Updated 2FA status in memory fallback due to DB error' });
      }
      return reply.code(500).send({ error: 'Failed to update two-factor configuration.' });
    }
  });

  // Username Check Endpoint
  fastify.get('/username-check', async (request, reply) => {
    const ip = request.ip;
    if (!await checkRateLimit(ip)) {
      return reply.code(429).send({ error: 'Too many requests. Please wait a minute.' });
    }

    const { username } = request.query as any;
    if (!username) {
      return reply.code(400).send({ error: 'Username query parameter is required' });
    }

    const cleanUsername = username.toLowerCase().trim();

    try {
      const result = await pool.query('SELECT id FROM users WHERE username = $1', [cleanUsername]);
      if (result.rows.length > 0) {
        return reply.send({ available: false });
      }
    } catch (err: any) {
      console.warn('Postgres query failure for username checking, using memory:', err.message);
    }

    const existsInMemory = inMemoryUsers.some(u => u.username === cleanUsername);
    return reply.send({ available: !existsInMemory });
  });

  // Register/Update Push Token Endpoint
  fastify.post('/push-token', async (request, reply) => {
    const authHeader = request.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return reply.code(401).send({ error: 'Unauthorized: Missing or invalid authorization header' });
    }

    const token = authHeader.split(' ')[1];
    let userId: string;
    try {
      const decoded = jwt.verify(token, JWT_SECRET) as { userId: string };
      userId = decoded.userId;
    } catch (err) {
      return reply.code(401).send({ error: 'Unauthorized: Invalid token' });
    }

    const { pushToken } = request.body as any;
    if (!pushToken) {
      return reply.code(400).send({ error: 'Missing pushToken in request body' });
    }

    try {
      const result = await pool.query(
        'UPDATE users SET push_token = $1 WHERE id = $2 RETURNING id',
        [pushToken, userId]
      );

      if (result.rowCount === 0) {
        const memoryUser = inMemoryUsers.find(u => u.id === userId);
        if (memoryUser) {
          inMemoryPushTokens.set(userId, pushToken);
          return reply.send({ success: true, note: 'Updated push token in memory fallback' });
        }
        return reply.code(404).send({ error: 'User not found' });
      }

      return reply.send({ success: true });
    } catch (err: any) {
      console.warn('Failed to update push token in Postgres, trying memory:', err.message);
      inMemoryPushTokens.set(userId, pushToken);
      return reply.send({ success: true, note: 'Updated push token in memory fallback due to DB error' });
    }
  });
}
