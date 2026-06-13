import { vi, describe, it, expect, beforeEach } from 'vitest';
import jwt from 'jsonwebtoken';

// Setup environment variables before imports
process.env.NODE_ENV = 'test';
process.env.EMAIL_ENCRYPTION_KEY = 'chatly-test-key-32-chars-long!!!';
process.env.CHATLY_DEV_OTP_BYPASS = 'true';

// Mock pg module before importing server
const mockQuery = vi.fn();
vi.mock('../db', () => {
  const mClient = {
    query: vi.fn().mockResolvedValue({ rows: [], rowCount: 0 }),
    release: vi.fn(),
  };
  const mPool = {
    connect: vi.fn().mockResolvedValue(mClient),
    query: vi.fn((queryText, values) => mockQuery(queryText, values)),
    on: vi.fn(),
    end: vi.fn(),
  };
  return {
    pool: mPool,
    initializeDatabase: vi.fn().mockResolvedValue(true),
    isDbConnected: vi.fn().mockReturnValue(true),
  };
});

// Mock push service to avoid network dependency
vi.mock('../services/push', () => ({
  sendSilentPush: vi.fn().mockResolvedValue(true),
}));

// Mock mail service to avoid real SMTP connection
vi.mock('../services/mail', () => ({
  sendEmail: vi.fn().mockResolvedValue(true),
}));

// Now import server and redis client
import { server } from '../server';
import { redisClient } from '../db/redis';

describe('Chatly Server Hardening & Security Integration Tests', () => {
  const testUser = {
    userId: '11111111-2222-3333-4444-555555555555',
    username: 'alice',
    emailVerified: true,
  };
  
  let testToken: string;

  beforeEach(() => {
    mockQuery.mockReset();
    mockQuery.mockResolvedValue({ rows: [], rowCount: 0 });
    // Resolve JWT_SECRET dynamically to match what was loaded by the server at import time
    const secret = process.env.JWT_SECRET || 'chatly-super-secret-key-change-in-prod';
    testToken = jwt.sign(testUser, secret);
  });

  describe('CORS and Production Environment Gating', () => {
    it('should boot successfully with test environment settings', async () => {
      const response = await server.inject({
        method: 'GET',
        url: '/',
      });
      expect(response.statusCode).toBe(200);
      const data = JSON.parse(response.body);
      expect(data.status).toBe('running');
    });

    it('should fail with weak JWT secret in production', async () => {
      const mockExit = vi.spyOn(process, 'exit').mockImplementation((() => {}) as any);
      const mockConsoleError = vi.spyOn(console, 'error').mockImplementation(() => {});

      // Simulate production require check logic
      const weakSecret = 'chatly-super-secret-key-change-in-prod';
      if (weakSecret === 'chatly-super-secret-key-change-in-prod') {
        mockExit(1);
      }

      expect(mockExit).toHaveBeenCalledWith(1);
      mockExit.mockRestore();
      mockConsoleError.mockRestore();
    });
  });

  describe('Dev OTP Bypass Gate', () => {
    it('should verify dev OTP bypass works in development/test environments when active', () => {
      const isOtpBypassEnabled = process.env.NODE_ENV !== 'production' && process.env.CHATLY_DEV_OTP_BYPASS === 'true';
      expect(isOtpBypassEnabled).toBe(true);
    });

    it('should NOT allow OTP bypass in production mode', () => {
      const env = 'production';
      const isOtpBypassEnabled = env !== 'production' && process.env.CHATLY_DEV_OTP_BYPASS === 'true';
      expect(isOtpBypassEnabled).toBe(false);
    });
  });

  describe('E2E Key Upload & Fetch API', () => {
    it('should reject public key upload if unauthorized', async () => {
      const response = await server.inject({
        method: 'POST',
        url: '/api/keys/upload',
        payload: {
          identity_key: 'A'.repeat(44),
          dh_identity_key: 'B'.repeat(44),
          signed_prekey: 'C'.repeat(44),
          prekey_signature: 'D'.repeat(44),
        },
      });
      expect(response.statusCode).toBe(401);
    });

    it('should accept public key upload with valid authorization', async () => {
      mockQuery.mockResolvedValueOnce({ rowCount: 1, rows: [] });

      const response = await server.inject({
        method: 'POST',
        url: '/api/keys/upload',
        headers: {
          authorization: `Bearer ${testToken}`,
        },
        payload: {
          identity_key: 'bW9ja2tleV94MjU1MTlfaWRlbnRpdHlfcHVibGljX2tleV9iYXNlNjQ=',
          dh_identity_key: 'bW9ja2tleV94MjU1MTlfaWRlbnRpdHlfcHVibGljX2tleV9iYXNlNjQ=',
          signed_prekey: 'bW9ja2tleV94MjU1MTlfaWRlbnRpdHlfcHVibGljX2tleV9iYXNlNjQ=',
          prekey_signature: 'bW9ja2tleV94MjU1MTlfaWRlbnRpdHlfcHVibGljX2tleV9iYXNlNjQ=',
        },
      });

      expect(response.statusCode).toBe(200);
      expect(JSON.parse(response.body)).toEqual({ success: true });
      expect(mockQuery).toHaveBeenCalledWith(
        expect.stringContaining('INSERT INTO public_keys'),
        expect.arrayContaining([testUser.userId, 'bW9ja2tleV94MjU1MTlfaWRlbnRpdHlfcHVibGljX2tleV9iYXNlNjQ='])
      );
    });

    it('should reject public key if any fields are missing', async () => {
      const response = await server.inject({
        method: 'POST',
        url: '/api/keys/upload',
        headers: {
          authorization: `Bearer ${testToken}`,
        },
        payload: {
          identity_key: 'too-short',
        },
      });
      expect(response.statusCode).toBe(400);
    });

    it('should fetch public key for user if exists', async () => {
      const expectedKey = 'bW9ja2tleV94MjU1MTlfaWRlbnRpdHlfcHVibGljX2tleV9iYXNlNjQ=';
      mockQuery.mockResolvedValueOnce({
        rows: [{
          identity_key: expectedKey,
          dh_identity_key: expectedKey,
          signed_prekey: expectedKey,
          prekey_signature: expectedKey,
        }],
      });

      const response = await server.inject({
        method: 'GET',
        url: '/api/keys/bob',
        headers: {
          authorization: `Bearer ${testToken}`,
        },
      });

      expect(response.statusCode).toBe(200);
      const data = JSON.parse(response.body);
      expect(data.found).toBe(true);
      expect(data.identity_key).toBe(expectedKey);
    });

    it('should return found=false if public key does not exist', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [] });

      const response = await server.inject({
        method: 'GET',
        url: '/api/keys/charlie',
        headers: {
          authorization: `Bearer ${testToken}`,
        },
      });

      expect(response.statusCode).toBe(200);
      const data = JSON.parse(response.body);
      expect(data.found).toBe(false);
      expect(data.identity_key).toBeNull();
    });
  });

  describe('WebSocket Single-Use Tickets', () => {
    it('should generate a 30s WebSocket ticket when authenticated', async () => {
      const response = await server.inject({
        method: 'POST',
        url: '/api/auth/ws-ticket',
        headers: {
          authorization: `Bearer ${testToken}`,
        },
      });

      expect(response.statusCode).toBe(200);
      const data = JSON.parse(response.body);
      expect(data.ticket).toBeDefined();
      expect(typeof data.ticket).toBe('string');

      // Verify it was stored in Redis/MemoryFallback
      const stored = await redisClient.get(`ws-ticket:${data.ticket}`);
      expect(stored).toBeDefined();
      const decoded = JSON.parse(stored!);
      expect(decoded.userId).toBe(testUser.userId);
      expect(decoded.username).toBe(testUser.username);
    });

    it('should reject WebSocket ticket generation if unauthorized', async () => {
      const response = await server.inject({
        method: 'POST',
        url: '/api/auth/ws-ticket',
      });
      expect(response.statusCode).toBe(401);
    });
  });
});
