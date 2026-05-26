import { Pool } from 'pg';
import dotenv from 'dotenv';

dotenv.config();

// Pool configuration
// If DATABASE_URL is not provided, we fall back to a mock/in-memory style or local postgres connection.
const databaseUrl = process.env.DATABASE_URL || 'postgresql://postgres:postgres@localhost:5432/chatly';

const isRemoteDb = !databaseUrl.includes('localhost') && !databaseUrl.includes('127.0.0.1');

export const pool = new Pool({
  connectionString: databaseUrl,
  ssl: isRemoteDb ? { rejectUnauthorized: false } : false,
  connectionTimeoutMillis: 5000,
  idleTimeoutMillis: 10000,
});


// Helper to initialize tables
export async function initializeDatabase() {
  try {
    console.log('Connecting to PostgreSQL database...');
    const client = await pool.connect();
    try {
      console.log('Initializing database schema...');
      
      // Create Users Table
      await client.query(`
        CREATE TABLE IF NOT EXISTS users (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          email_hash VARCHAR(255) UNIQUE NOT NULL,
          email_encrypted TEXT NOT NULL,
          username VARCHAR(50) UNIQUE NOT NULL,
          avatar_color VARCHAR(10) NOT NULL,
          bio VARCHAR(100) DEFAULT '',
          mood VARCHAR(50) DEFAULT '🎵 Vibing',
          tier VARCHAR(10) DEFAULT 'free',
          push_token VARCHAR(255),
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          last_active_at DATE DEFAULT CURRENT_DATE,
          is_banned BOOLEAN DEFAULT FALSE,
          ban_until TIMESTAMP
        );
      `);

      // Ensure push_token exists on legacy databases
      await client.query(`
        ALTER TABLE users ADD COLUMN IF NOT EXISTS push_token VARCHAR(255);
      `);

      // Ensure email_verified and two_factor_enabled columns exist
      await client.query(`
        ALTER TABLE users ADD COLUMN IF NOT EXISTS email_verified BOOLEAN DEFAULT FALSE;
      `);
      await client.query(`
        ALTER TABLE users ADD COLUMN IF NOT EXISTS two_factor_enabled BOOLEAN DEFAULT FALSE;
      `);

      // Create Email Verifications Table
      await client.query(`
        CREATE TABLE IF NOT EXISTS email_verifications (
          email VARCHAR(255) PRIMARY KEY,
          code VARCHAR(6) NOT NULL,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          expires_at TIMESTAMP NOT NULL
        );
      `);

      // Create Two-Factor Temp Login Codes Table
      await client.query(`
        CREATE TABLE IF NOT EXISTS two_factor_temp (
          user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
          code VARCHAR(6) NOT NULL,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          expires_at TIMESTAMP NOT NULL
        );
      `);

      // Create Public Keys Table (for E2E Signal Protocol exchange)
      await client.query(`
        CREATE TABLE IF NOT EXISTS public_keys (
          user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
          identity_key TEXT NOT NULL,
          signed_prekey TEXT NOT NULL,
          prekey_signature TEXT NOT NULL,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
      `);

      // Create Friendships / Connections Table
      await client.query(`
        CREATE TABLE IF NOT EXISTS friendships (
          user_id_a UUID REFERENCES users(id) ON DELETE CASCADE,
          user_id_b UUID REFERENCES users(id) ON DELETE CASCADE,
          status VARCHAR(20) DEFAULT 'pending', -- pending, accepted, blocked
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (user_id_a, user_id_b)
        );
      `);

      // Create Groups Table
      await client.query(`
        CREATE TABLE IF NOT EXISTS groups (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          name VARCHAR(100) NOT NULL,
          description VARCHAR(255) DEFAULT '',
          created_by UUID REFERENCES users(id) ON DELETE SET NULL,
          max_members INT DEFAULT 25,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
      `);

      // Create Group Members Join Table
      await client.query(`
        CREATE TABLE IF NOT EXISTS group_members (
          group_id UUID REFERENCES groups(id) ON DELETE CASCADE,
          user_id UUID REFERENCES users(id) ON DELETE CASCADE,
          role VARCHAR(20) DEFAULT 'member', -- admin, member
          joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (group_id, user_id)
        );
      `);

      // Create Pulse Posts Table (Lucky Pulse anonymous feed)
      await client.query(`
        CREATE TABLE IF NOT EXISTS pulse_posts (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          author_id UUID REFERENCES users(id) ON DELETE CASCADE,
          text VARCHAR(200) NOT NULL,
          topics JSONB DEFAULT '[]',
          seen_count INT DEFAULT 0,
          replies_count INT DEFAULT 0,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
      `);

      // Auto-clean pulse posts older than 7 days (runs on each server start)
      await client.query(`
        DELETE FROM pulse_posts WHERE created_at < NOW() - INTERVAL '7 days';
      `);

      // Ensure bio/mood columns exist on older DBs
      await client.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS bio VARCHAR(100) DEFAULT '';`);
      await client.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS mood VARCHAR(50) DEFAULT '🎵 Vibing';`);

      console.log('Database schema verified successfully.');
    } catch (err) {
      console.error('Failed to initialize database schema:', err);
    } finally {
      client.release();
    }
  } catch (err: any) {
    console.error('Failed to connect to PostgreSQL database:', err.message);
    if (process.env.NODE_ENV === 'production') {
      throw new Error(`Database connection failed: ${err.message}`);
    }
    console.warn(
      'Failed to connect to PostgreSQL database:\n' +
      err.message + '\n' +
      'Server will run in automatic memory fallback mode for database storage.'
    );
  }
}
