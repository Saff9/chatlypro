# Chatly — Claude Code Context

This file gives Claude Code the project-level context it needs to assist effectively.

## Repo Layout

```
chatly/
├── apps/mobile/                  # Flutter client (Android, iOS, Web, Windows)
│   └── lib/
│       ├── core/                 # Shared widgets (BeautifulAvatar), theme tokens, AppConfig
│       ├── features/
│       │   ├── auth/             # Login, register, 2FA, email verification screens
│       │   ├── chat/
│       │   │   ├── data/models/  # MessageData model
│       │   │   └── presentation/
│       │   │       ├── screens/  # chat_screen.dart (state + build), chat_list_screen.dart
│       │   │       └── widgets/  # message_bubble.dart, chat_input_bar.dart, chat_painters.dart
│       │   ├── groups/           # Group list + group chat screen
│       │   └── settings/         # Settings, security, theme, profile screens
│       ├── navigation/           # Main bottom-nav shell (main_navigation.dart)
│       ├── providers/            # Riverpod state (connection, layout, wallpaper, theme)
│       └── services/             # Business logic: auth, websocket, encryption, storage
└── packages/chatly-server/       # Fastify + Node.js relay backend
    └── src/
        ├── db/                   # PostgreSQL schema init (index.ts) + Redis client (redis.ts)
        ├── routes/               # REST: auth.ts, keys.ts, social.ts
        ├── services/             # Email (mail.ts), push notifications (push.ts)
        └── sockets/              # WebSocket handler (chat.ts)
```

## Architecture Decisions

| Layer | Choice | Why |
|---|---|---|
| State management | Riverpod `StateNotifierProvider` | Compile-safe, no BuildContext dependency |
| Local storage | Hive encrypted boxes | Pure Dart, no JNI overhead |
| Transport | WebSocket (ws library) | Persistent connection, low overhead for real-time |
| Auth | JWT + single-use WS tickets | Tickets prevent JWT from appearing in server logs |
| 1-to-1 encryption | Signal Protocol (X3DH-Lite + Double Ratchet) | Forward secrecy + break-in recovery |
| Group encryption | ECIES (ephemeral X25519 + HKDF + AES-256-GCM) | Per-member key wrapping, server is zero-knowledge |
| Offline queue | Redis `msg:{username}:{uuid}` with 24 h TTL | Falls back to bounded in-memory Map |

## Key Invariants

- **The server never sees plaintext.** All ciphertext is opaque to the relay.
- **Single active WebSocket per user.** A new connection closes the previous one (code 4009).
- **Hive box naming**: messages are in `messages_{username}` for DMs and `messages_group_{groupId}` for groups. The outbox (unsent messages) is the `outbox` box.
- **Session state** (Double Ratchet) lives in `secure_vault` under the key `session_{username}`.
- **Navigation tabs**: `['chats', 'groups', 'settings']` — Pulse, Calculator disguise, and Shake-to-panic were removed.

## Service Responsibilities

| File | Responsibility |
|---|---|
| `websocket_service.dart` | WebSocket lifecycle, send with outbox fallback, typing throttle, adaptive pings |
| `encryption_service.dart` | X3DH-Lite session init (initiator + receiver), Double Ratchet encrypt/decrypt, ECIES group key wrap/unwrap |
| `auth_service.dart` | Login, register, JWT refresh, key generation and upload |
| `message_storage_service.dart` | Hive CRUD for messages, forensic erase, 50-message sliding limit |
| `api_service.dart` | All REST calls via Dio; adds `Authorization: Bearer <jwt>` header |
| `push_notification_service.dart` | Background vault message display, push token registration |

## Common Pitfalls

- `_handleIncomingSocketPayload` in `chat_screen.dart` must handle `sent_ack` (server confirmation) **before** filtering by `senderId`. `sent_ack` events have no `senderId`.
- Offline messages stored in Redis use `{ senderId, ciphertext, timestamp, groupId? }` — spread at the top level, not nested under `data`.
- Typing throttle is per-recipient (`Map<String, DateTime> _lastTypingSentMap`) — one global timer caused cross-chat suppression.
- `acceptInvitation` and `rejectInvitation` **remove** the invite from the list entirely (don't change status). The UI relies on this to update immediately.
- `ConnectionInvite` no longer has `isProximity`. Old Hive data with that field deserialises safely (field is ignored in `fromJson`).

## Running Locally

```bash
# Backend
cd packages/chatly-server && npm install && npm run dev

# Flutter
cd apps/mobile && flutter pub get && flutter run -d chrome
```

## Environment Variables (server)

| Variable | Required | Description |
|---|---|---|
| `DATABASE_URL` | No | PostgreSQL DSN. Falls back to in-memory. |
| `REDIS_URL` | No | Upstash / Redis URL. Falls back to in-memory Map. |
| `JWT_SECRET` | **Yes (prod)** | ≥ 32 random characters. |
| `EMAIL_ENCRYPTION_KEY` | No | 32-byte key for encrypting email addresses at rest. |
| `ALLOWED_ORIGINS` | No | Comma-separated CORS origin whitelist. |
