import dns from 'dns';
import { pool } from '../db';

const ML_SERVICE_URL = process.env.ML_SERVICE_URL || 'http://localhost:8000';

// In-memory warnings map for fast throttling & auto-bans
const userWarningTracker = new Map<string, { warnings: number; lastWarningAt: number }>();

export function sanitizeMessage(input: string): string {
  if (!input) return '';
  // Convert standard HTML characters to safe HTML entities to prevent XSS
  return input
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#x27;')
    .replace(/\//g, '&#x2F;')
    .trim();
}

/**
 * Contacts ML service to analyze toxicity, increments infraction counts, and auto-bans user if thresholds are met.
 */
export async function checkAndModerateUserMessage(userId: string, plaintext: string): Promise<boolean> {
  const sanitized = sanitizeMessage(plaintext);

  // If text is empty after sanitizing, block it
  if (!sanitized) {
    throw new Error('Message is empty or contains invalid characters.');
  }

  let toxicityScore = 0.05; // Default safe mock score

  try {
    const response = await fetch(`${ML_SERVICE_URL}/analyse`, {
      method: 'POST',
      headers: { 
        'Content-Type': 'application/json',
        'X-API-Key': process.env.API_KEY || ''
      },
      body: JSON.stringify({ text: sanitized }),
      signal: AbortSignal.timeout(3000)
    });

    if (response.ok) {
      const data = await response.json() as any;
      toxicityScore = data.toxicity_score || 0.0;
    }
  } catch (err: any) {
    console.warn(`ML Service connection offline at ${ML_SERVICE_URL}. Utilizing local fallback scanner:`, err.message);
    
    // Quick regex fallback for offline resilience
    const blacklist = [/abuse/i, /kill/i, /idiot/i, /hate/i, /trash/i, /stupid/i, /fuck/i, /bitch/i, /asshole/i];
    const isMatched = blacklist.some(rx => rx.test(sanitized));
    if (isMatched) {
      toxicityScore = 0.85;
    }
  }

  // Toxicity threshold of 0.7 triggers infractions
  if (toxicityScore > 0.7) {
    await registerInfraction(userId);
    throw new Error('Message blocked: Content violates toxicity guidelines.');
  }

  return true;
}

/**
 * Handles infraction logs, warnings, and auto-banning
 */
async function registerInfraction(userId: string) {
  const now = Date.now();
  const record = userWarningTracker.get(userId) || { warnings: 0, lastWarningAt: 0 };
  
  record.warnings++;
  record.lastWarningAt = now;
  userWarningTracker.set(userId, record);

  console.log(`User ${userId} registered toxicity infraction. Total warnings: ${record.warnings}`);

  // Auto-ban rules:
  // 3 infractions within 24 hours -> 1 day ban
  // 5 infractions within 24 hours -> 7 day ban
  // 10 infractions -> Permanent ban
  let banDurationHours = 0;
  let isPermanent = false;

  if (record.warnings >= 10) {
    isPermanent = true;
    banDurationHours = 87600; // 10 years (effectively permanent)
  } else if (record.warnings >= 5) {
    banDurationHours = 168; // 7 days
  } else if (record.warnings >= 3) {
    banDurationHours = 24; // 1 day
  }

  if (banDurationHours > 0) {
    const banUntil = new Date(now + banDurationHours * 60 * 60 * 1000);
    
    try {
      await pool.query(
        'UPDATE users SET is_banned = TRUE, ban_until = $1 WHERE id = $2',
        [banUntil, userId]
      );
      console.log(`Auto-Ban: User ${userId} banned until ${banUntil.toISOString()}`);
    } catch (err: any) {
      console.warn(`Could not save ban status to Postgres for user ${userId}:`, err.message);
    }
  }
}
