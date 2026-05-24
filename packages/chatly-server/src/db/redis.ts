import Redis from 'ioredis';
import dotenv from 'dotenv';

dotenv.config();

const redisUrl = process.env.REDIS_URL;

class MemoryFallback {
  private store = new Map<string, { value: string; expiry: number | null }>();

  async get(key: string): Promise<string | null> {
    const item = this.store.get(key);
    if (!item) return null;
    if (item.expiry && Date.now() > item.expiry) {
      this.store.delete(key);
      return null;
    }
    return item.value;
  }

  async set(key: string, value: string, mode?: string, duration?: number): Promise<'OK'> {
    let expiry: number | null = null;
    if (mode === 'EX' && duration) {
      expiry = Date.now() + duration * 1000;
    }
    this.store.set(key, { value, expiry });
    return 'OK';
  }

  async del(key: string): Promise<number> {
    const exists = this.store.has(key);
    this.store.delete(key);
    return exists ? 1 : 0;
  }

  async keys(pattern: string): Promise<string[]> {
    const regex = new RegExp('^' + pattern.replace(/\*/g, '.*') + '$');
    const matches: string[] = [];
    const now = Date.now();
    for (const [key, item] of this.store.entries()) {
      if (item.expiry && now > item.expiry) {
        this.store.delete(key);
        continue;
      }
      if (regex.test(key)) {
        matches.push(key);
      }
    }
    return matches;
  }
}

// Instantiate Redis Client or use MemoryFallback
let redisClient: Redis | MemoryFallback;

if (redisUrl) {
  console.log('Connecting to Upstash/External Redis...');
  const client = new Redis(redisUrl);
  client.on('error', (err) => {
    console.error('Redis connection error, falling back to memory storage:', err);
    redisClient = new MemoryFallback();
  });
  redisClient = client;
} else {
  console.log('No REDIS_URL found. Utilizing safe in-memory fallback cache.');
  redisClient = new MemoryFallback();
}

export { redisClient };
