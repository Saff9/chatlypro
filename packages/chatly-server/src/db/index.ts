import { Pool, PoolClient } from 'pg';
import dotenv from 'dotenv';

dotenv.config();

// ─── Connection String Sanitization ──────────────────────────────────────────
// Handles special characters in passwords. Does NOT rewrite hosts or ports.
// The DATABASE_URL in Render env vars must be the correct pooler connection string.
function sanitizeDatabaseUrl(url: string): string {
  try {
    // Strip sslmode param so our programmatic SSL config always wins
    let clean = url
      .replace(/([?&])sslmode=[^&]*/gi, '')
      .replace(/([?&])ssl=[^&]*/gi, '')
      .replace(/\?&/g, '?')
      .replace(/\?$/, '')
      .replace(/&$/, '');

    const protoEnd = clean.indexOf('://');
    if (protoEnd === -1) return clean;
    const proto = clean.slice(0, protoEnd + 3);
    const rest = clean.slice(protoEnd + 3);
    const atIdx = rest.lastIndexOf('@');
    if (atIdx === -1) return clean;
    const creds = rest.slice(0, atIdx);
    const hostPart = rest.slice(atIdx + 1);
    const colonIdx = creds.indexOf(':');
    if (colonIdx === -1) return clean;
    const user = creds.slice(0, colonIdx);
    const pass = creds.slice(colonIdx + 1);

    // Encode special chars in password that break URL parsing
    const encodedPass = /[#@]/.test(pass) ? encodeURIComponent(pass) : pass;
    return `${proto}${user}:${encodedPass}@${hostPart}`;
  } catch {
    return url;
  }
}

const rawUrl = process.env.DATABASE_URL || '';
const isLocal = !rawUrl || rawUrl.includes('localhost') || rawUrl.includes('127.0.0.1');

const databaseUrl = rawUrl ? sanitizeDatabaseUrl(rawUrl) : 'postgresql://postgres:postgres@localhost:5432/chatly';

// ─── Diagnostic: print sanitized connection info (no password) ────────────────
try {
  const u = new URL(databaseUrl);
  console.log(`[Database] Connecting to: host=${u.hostname} port=${u.port || 5432} user=${u.username} db=${u.pathname.slice(1)}`);
} catch {
  console.log('[Database] Could not parse DATABASE_URL for diagnostic logging.');
}

// ─── SSL Configuration ────────────────────────────────────────────────────────
// For remote connections: allow SSL but don't reject self-signed certs.
// Supabase uses a self-signed CA by default. rejectUnauthorized:false is fine
// because the connection is already encrypted and Supabase's network is trusted.
const sslConfig = isLocal ? false : { rejectUnauthorized: false };

// ─── Connection Pool ──────────────────────────────────────────────────────────
export const pool = new Pool({
  connectionString: databaseUrl,
  ssl: sslConfig,
  max: 10,
  min: 2,
  connectionTimeoutMillis: 10_000,
  idleTimeoutMillis: 30_000,
  allowExitOnIdle: false,
});

pool.on('error', (err) => {
  console.error('[Database] Idle pool client error:', err.message);
});

// ─── Schema DDL ──────────────────────────────────────────────────────────────
const SCHEMA_SQL = `
  CREATE EXTENSION IF NOT EXISTS pgcrypto;

  CREATE TABLE IF NOT EXISTS users (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email_hash       VARCHAR(255) UNIQUE NOT NULL,
    email_encrypted  TEXT NOT NULL,
    password_hash    VARCHAR(255),
    username         VARCHAR(50) UNIQUE NOT NULL,
    avatar_color     VARCHAR(10) NOT NULL,
    bio              VARCHAR(100) DEFAULT '',
    mood             VARCHAR(50) DEFAULT '🎵 Vibing',
    tier             VARCHAR(10) DEFAULT 'free',
    push_token       VARCHAR(255),
    email_verified   BOOLEAN DEFAULT FALSE,
    two_factor_enabled BOOLEAN DEFAULT FALSE,
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_active_at   DATE DEFAULT CURRENT_DATE,
    is_banned        BOOLEAN DEFAULT FALSE,
    ban_until        TIMESTAMP
  );

  ALTER TABLE users ADD COLUMN IF NOT EXISTS push_token VARCHAR(255);
  ALTER TABLE users ADD COLUMN IF NOT EXISTS password_hash VARCHAR(255);
  ALTER TABLE users ADD COLUMN IF NOT EXISTS email_verified BOOLEAN DEFAULT FALSE;
  ALTER TABLE users ADD COLUMN IF NOT EXISTS two_factor_enabled BOOLEAN DEFAULT FALSE;
  ALTER TABLE users ADD COLUMN IF NOT EXISTS bio VARCHAR(100) DEFAULT '';
  ALTER TABLE users ADD COLUMN IF NOT EXISTS mood VARCHAR(50) DEFAULT '🎵 Vibing';

  CREATE TABLE IF NOT EXISTS email_verifications (
    email       VARCHAR(255) PRIMARY KEY,
    code        VARCHAR(6) NOT NULL,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at  TIMESTAMP NOT NULL
  );

  CREATE TABLE IF NOT EXISTS two_factor_temp (
    user_id    UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    code       VARCHAR(6) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP NOT NULL
  );

  CREATE TABLE IF NOT EXISTS public_keys (
    user_id           UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    identity_key      TEXT NOT NULL,
    signed_prekey     TEXT NOT NULL,
    prekey_signature  TEXT NOT NULL,
    updated_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  );

  CREATE TABLE IF NOT EXISTS friendships (
    user_id_a  UUID REFERENCES users(id) ON DELETE CASCADE,
    user_id_b  UUID REFERENCES users(id) ON DELETE CASCADE,
    status     VARCHAR(20) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id_a, user_id_b)
  );

  CREATE TABLE IF NOT EXISTS groups (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        VARCHAR(100) NOT NULL,
    description VARCHAR(255) DEFAULT '',
    created_by  UUID REFERENCES users(id) ON DELETE SET NULL,
    max_members INT DEFAULT 25,
    expires_at  TIMESTAMP,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  );

  ALTER TABLE groups ADD COLUMN IF NOT EXISTS expires_at TIMESTAMP;

  CREATE TABLE IF NOT EXISTS group_members (
    group_id   UUID REFERENCES groups(id) ON DELETE CASCADE,
    user_id    UUID REFERENCES users(id) ON DELETE CASCADE,
    role       VARCHAR(20) DEFAULT 'member',
    joined_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (group_id, user_id)
  );

  CREATE TABLE IF NOT EXISTS group_messages (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id   UUID REFERENCES groups(id) ON DELETE CASCADE,
    sender_id  UUID REFERENCES users(id) ON DELETE CASCADE,
    text       TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  );

  CREATE TABLE IF NOT EXISTS pulse_posts (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    author_id     UUID REFERENCES users(id) ON DELETE CASCADE,
    text          VARCHAR(200) NOT NULL,
    topics        JSONB DEFAULT '[]',
    replies_count INT DEFAULT 0,
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  );

  ALTER TABLE pulse_posts DROP COLUMN IF EXISTS seen_count;
  DELETE FROM pulse_posts WHERE created_at < NOW() - INTERVAL '7 days';
`;

// ─── Database Initialization ──────────────────────────────────────────────────
// Retries up to maxAttempts times with exponential backoff.
// Does NOT crash the server on failure - logs the error and returns.
export async function initializeDatabase(maxAttempts = 3): Promise<boolean> {
  let lastError: Error | null = null;

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    let client: PoolClient | null = null;
    try {
      console.log(`[Database] Connecting (attempt ${attempt}/${maxAttempts})...`);
      client = await pool.connect();
      console.log('[Database] Connected. Applying schema...');
      await client.query(SCHEMA_SQL);
      console.log('[Database] Schema ready.');
      return true;
    } catch (err: any) {
      lastError = err;
      console.error(`[Database] Attempt ${attempt} failed: ${err.message}`);
      if (client) {
        try { client.release(true); } catch { /* ignore */ }
        client = null;
      }
      if (attempt < maxAttempts) {
        const delay = attempt * 2000;
        console.log(`[Database] Retrying in ${delay / 1000}s...`);
        await new Promise((r) => setTimeout(r, delay));
      }
    } finally {
      if (client) {
        try { client.release(); } catch { /* ignore */ }
      }
    }
  }

  // All attempts failed - log but DO NOT throw.
  // The server will start up and return errors from DB-dependent routes.
  console.error(`[Database] All ${maxAttempts} connection attempts failed. Last error: ${lastError?.message}`);
  console.error('[Database] Server will start without a database connection. Fix DATABASE_URL in Render environment variables.');
  return false;
}
