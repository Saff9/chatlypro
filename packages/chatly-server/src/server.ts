import fastify from 'fastify';
import fastifyWebsocket from '@fastify/websocket';
import fastifyCors from '@fastify/cors';
import dotenv from 'dotenv';
import { initializeDatabase } from './db';
import { authRoutes } from './routes/auth';
import { handleWebSocketConnection } from './sockets/chat';

// Load environment variables from .env file in development.
// In production (Railway, Render, etc.) these are injected directly by the platform.
dotenv.config();

// ─── Environment Validation ──────────────────────────────────────────────────
// Refuse to boot with the default dev secret in production.
// This prevents accidentally launching with an insecure signing key.
const JWT_SECRET = process.env.JWT_SECRET ?? 'chatly-super-secret-key-change-in-prod';
const NODE_ENV = process.env.NODE_ENV ?? 'development';

if (NODE_ENV === 'production' && JWT_SECRET === 'chatly-super-secret-key-change-in-prod') {
  console.error('[FATAL] JWT_SECRET must be set to a strong random value in production. Refusing to start.');
  process.exit(1);
}

if (JWT_SECRET.length < 32) {
  console.warn('[WARN] JWT_SECRET is shorter than 32 characters. Use a longer, random value for production.');
}

// ─── CORS Configuration ───────────────────────────────────────────────────────
// In development, all origins are allowed so local Flutter/web clients connect
// without configuration. In production, restrict to the actual client domains
// by setting ALLOWED_ORIGINS in your environment (comma-separated list).
const allowedOrigins = process.env.ALLOWED_ORIGINS
  ? process.env.ALLOWED_ORIGINS.split(',').map((o) => o.trim())
  : true; // true = allow any origin (development fallback)

// ─── Server Initialization ────────────────────────────────────────────────────
const server = fastify({
  logger: {
    // Pretty-print in dev for readability; use JSON in production for log aggregators.
    transport: NODE_ENV !== 'production'
      ? { target: 'pino-pretty', options: { colorize: true } }
      : undefined,
  },
});

// Register CORS before any other plugins so preflight responses are handled
// before route handlers execute.
server.register(fastifyCors, {
  origin: allowedOrigins,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: true,
});

// ─── Security Response Headers ────────────────────────────────────────────────
// Applied globally to every response. These protect against common web attacks
// such as clickjacking, MIME sniffing, and data leakage via Referer headers.
server.addHook('onRequest', async (request, reply) => {
  reply.header('X-DNS-Prefetch-Control', 'off');
  reply.header('X-Frame-Options', 'DENY');
  reply.header('X-Content-Type-Options', 'nosniff');
  reply.header('Referrer-Policy', 'no-referrer');
  reply.header('Content-Security-Policy', "default-src 'self'");
  reply.header('Permissions-Policy', 'geolocation=(), microphone=(), camera=()');
  // HSTS is only meaningful over HTTPS; safe to include anyway.
  reply.header('Strict-Transport-Security', 'max-age=63072000; includeSubDomains; preload');
});

// ─── Plugin Registration ──────────────────────────────────────────────────────
server.register(fastifyWebsocket);

// ─── REST Routes ──────────────────────────────────────────────────────────────
server.register(authRoutes, { prefix: '/api/auth' });

// ─── WebSocket Gateway ────────────────────────────────────────────────────────
// All real-time messaging flows through this single WS endpoint.
// The auth token is validated inside handleWebSocketConnection before any
// message routing occurs.
server.register(async (fastifyInstance) => {
  fastifyInstance.get('/ws/chat', { websocket: true }, (connection, req) => {
    handleWebSocketConnection(connection as any, req);
  });
});

// ─── Health Check ─────────────────────────────────────────────────────────────
server.get('/', async () => ({
  name: 'Chatly Secure Backend Relay',
  version: '1.0.0',
  environment: NODE_ENV,
  status: 'running',
  timestamp: new Date().toISOString(),
}));

// ─── Boot Sequence ────────────────────────────────────────────────────────────
const PORT = parseInt(process.env.PORT || '5000', 10);
const HOST = process.env.HOST || '0.0.0.0';

async function bootstrap() {
  try {
    await initializeDatabase();
    await server.listen({ port: PORT, host: HOST });
    server.log.info(`Chatly Secure Backend running on port ${PORT} [${NODE_ENV}]`);
  } catch (err) {
    server.log.error(err);
    process.exit(1);
  }
}

// ─── Graceful Shutdown ────────────────────────────────────────────────────────
// Cleanly drain open connections before the process exits.
// Required for zero-downtime rolling deployments on Railway / Render.
const gracefulShutdown = async (signal: string) => {
  server.log.info(`Received ${signal}. Shutting down gracefully...`);
  try {
    await server.close();
    server.log.info('Server closed cleanly. Goodbye.');
    process.exit(0);
  } catch (err) {
    server.log.error(err as Error, 'Error during graceful shutdown');
    process.exit(1);
  }
};

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT',  () => gracefulShutdown('SIGINT'));

bootstrap();
