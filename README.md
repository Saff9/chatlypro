<div align="center">

<img src="apps/mobile/assets/images/app_icon_v3.png" alt="Chatly Logo" width="100" height="100" style="border-radius: 22px;" />

# Chatly

**The secure, private, end-to-end encrypted messenger built for the real world.**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Node.js](https://img.shields.io/badge/Node.js-18.x-339933?style=for-the-badge&logo=nodedotjs&logoColor=white)](https://nodejs.org)
[![TypeScript](https://img.shields.io/badge/TypeScript-5.x-3178C6?style=for-the-badge&logo=typescript&logoColor=white)](https://www.typescriptlang.org)
[![Python](https://img.shields.io/badge/Python-3.10-3776AB?style=for-the-badge&logo=python&logoColor=white)](https://python.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=for-the-badge)](CONTRIBUTING.md)

*If you find Chatly useful, please consider giving it a ⭐ on GitHub — it helps others discover the project.*

[Features](#features) · [Architecture](#architecture) · [Quick Start](#quick-start) · [Deployment](#deployment) · [Roadmap](docs/ROADMAP.md) · [Security](docs/SECURITY.md)

</div>

---

## What is Chatly?

Chatly is a **privacy-first messaging platform** that combines a Flutter cross-platform client with a stateless Fastify relay and a Python FastAPI machine-learning moderation microservice.

Unlike conventional messaging apps that store message history on centralized servers, Chatly operates on a **zero-trace relay model**: messages are processed entirely in-memory and scrubbed the moment they are delivered. No message logs. No metadata retention. No surveillance surface.

---

## Features

### Security & Privacy
- **End-to-End Encryption** — X25519 Diffie-Hellman key exchange with AES-256-GCM symmetric encryption. Keys are generated on-device and never leave the client.
- **Zero-Trace Relay Pipeline** — The backend holds messages transiently in RAM (or Redis with a 24-hour TTL if the recipient is offline) and deletes them immediately upon delivery.
- **Email Verification & 2-Step Verification** — Every account goes through an email OTP gate. Optional TOTP-based second factor is available from the Security settings.
- **Disposable Email Blocking** — Server-side blocklist prevents sign-ups from known temporary mail providers.
- **Vault Chats** — Ephemeral on-device sessions that live entirely in RAM. Closing the session clears the memory heap.
- **Duress / Decoy Mode** — A secondary PIN unlocks a convincing decoy interface with innocent conversations. The real inbox remains hidden.
- **Calculator Disguise** — The app can masquerade as a working calculator. A secret code re-opens the real application.
- **Dead Man's Switch** — Configurable auto-wipe of all local data after a period of inactivity (default: 30 days).
- **Shake-to-Panic** — A quick device shake triggers an immediate decoy switch.
- **Forensic Eraser** — Multi-pass overwrite of deleted messages to prevent recovery by forensic tools.

### Messaging
- **Rich Chat Experience** — Voice messages, file attachments, reactions, read receipts, and typing indicators.
- **Message Reactions** — Six built-in reactions with an extensible backend catalogue.
- **Ephemeral Timers** — Per-message configurable self-destruct timers (30 s / 1 min / 5 min / 1 hr).
- **Secure Keyboard** — Optional on-screen keyboard that blocks screenshot capture and keyloggers.
- **AI Toxicity Moderation** — The FastAPI ML service classifies outgoing messages for toxic content using a fine-tuned BERT model (Detoxify), with a keyword regex fallback for zero-dependency deployments.

### Discovery & Community
- **Lucky Pulse** — Anonymous interest-based broadcast system. Post a message without revealing your identity. Mutual interest upgrades to a private encrypted chat.
- **Groups** — Fully encrypted group chats. Includes **Campfire Groups** — ephemeral groups that auto-dissolve and shred their logs after a user-defined timer.
- **P2P Mesh** — Offline messaging between nearby devices over a local UDP/TCP mesh network.
- **Proximity Pairing** — NFC-style close-proximity connection requests visible in the chat list.

### Personalization
- **15+ Themes** — Obsidian, Dracula, Cyberpunk, Deep Ocean, Emerald, and more.
- **Chat Wallpapers** — 5+ premium wallpapers built in. Swap or set custom.
- **Custom Fonts** — 5 curated typeface options including Inter and Roboto.
- **Smart Moods** — Custom status markers replace intrusive "last seen" timestamps.
- **Relationship Health Rings** — Visual engagement score rings on contact avatars based on message frequency.

---

## Architecture

```
chatly/
├── apps/
│   └── mobile/                   # Flutter client (Android · iOS · Web · Windows · macOS · Linux)
│       ├── assets/               # App icon, wallpapers, Lottie animations
│       └── lib/
│           ├── core/             # Shared widgets, theme tokens, AppConfig
│           ├── features/         # Screen-level feature modules (auth, chat, groups, pulse, settings)
│           ├── navigation/       # Bottom nav shell with adaptive desktop layout
│           ├── providers/        # Riverpod global state (theme, connection, layout, wallpaper)
│           └── services/         # Business logic (auth, websocket, E2E crypto, push, P2P)
│
├── packages/
│   ├── chatly-server/            # Fastify backend (Node.js + TypeScript)
│   │   └── src/
│   │       ├── db/               # PostgreSQL schema init + in-memory fallback
│   │       ├── routes/           # REST endpoints: /api/auth/*
│   │       ├── services/         # Email (Nodemailer + Ethereal), push tokens
│   │       └── sockets/          # WebSocket connection handler & message routing
│   │
│   └── chatly-ml/                # Python FastAPI ML microservice
│       ├── app.py                # FastAPI server + endpoint definitions
│       └── requirements.txt      # detoxify, torch, fastapi, uvicorn
│
├── docs/
│   ├── ARCHITECTURE.md           # Detailed technical architecture breakdown
│   ├── SECURITY.md               # Cryptographic flows and threat model
│   ├── DEVELOPMENT.md            # Local development setup
│   ├── HOSTING.md                # Production hosting guide (Railway, Supabase, Upstash)
│   ├── DEPLOYMENT.md             # APK / EXE / Web build instructions
│   └── ROADMAP.md                # Upcoming feature milestones
│
└── README.md
```

### Key Technical Decisions

| Decision | Rationale |
|---|---|
| **Fastify over Express** | 3× higher throughput, built-in schema validation, TypeScript-first |
| **Riverpod over Provider/Bloc** | Compile-safe, no BuildContext dependency, testable |
| **Hive over SQLite** | Pure Dart, encrypted boxes, no JNI overhead on Android |
| **X25519 + AES-256-GCM** | Best-in-class key agreement + authenticated encryption |
| **In-memory relay** | Zero-trace model: no message hits disk on the relay server |

---

## Quick Start

### Prerequisites
- [Node.js](https://nodejs.org) v18 or newer
- [Python](https://python.org) 3.10 or newer
- [Flutter SDK](https://flutter.dev/docs/get-started/install) 3.x

### 1. Clone the Repository
```bash
git clone https://github.com/Saff9/chatlypro.git
cd chatlypro
```

### 2. Start the Backend
```bash
cd packages/chatly-server
npm install
npm run dev
# Fastify starts on http://localhost:5000
# No database config needed — boots with in-memory fallback automatically.
```

### 3. Start the ML Service (Optional)
```bash
cd packages/chatly-ml
pip install -r requirements.txt
python app.py
# FastAPI starts on http://localhost:8000
```

### 4. Run the Flutter Client
```bash
cd apps/mobile
flutter pub get
flutter run -d chrome          # Web browser
flutter run -d windows         # Windows desktop
flutter run                    # Connected Android/iOS device
```

---

## Deployment

### Quick Deploy to Railway

[![Deploy on Railway](https://railway.app/button.svg)](https://railway.app)

### Quick Deploy to Render

[![Deploy on Render](https://render.com/images/deploy-button.svg)](https://render.com/deploy?repo=https://github.com/Saff9/chatlypro.git)

See the full step‑by‑step guide in [docs/HOSTING.md](docs/HOSTING.md).

### Build Release APK
```bash
cd apps/mobile
flutter build apk --release \
  --dart-define=BASE_URL=https://your-api-domain.com/api \
  --dart-define=WS_URL=wss://your-api-domain.com
```

### Build Windows EXE
```bash
cd apps/mobile
flutter build windows --release \
  --dart-define=BASE_URL=https://your-api-domain.com/api
```

See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for full platform-specific instructions.

---

## Environment Variables

| Variable | Required | Description |
|---|---|---|
| `DATABASE_URL` | No | PostgreSQL connection string. Falls back to in-memory store. |
| `REDIS_URL` | No | Upstash/Redis connection URL. Falls back to in-memory Map. |
| `JWT_SECRET` | **Yes (prod)** | Minimum 32-character random string for signing auth tokens. |
| `ALLOWED_ORIGINS` | No | Comma-separated CORS origin whitelist. Defaults to `*` in dev. |
| `PORT` | No | Server port. Defaults to `5000`. |
| `NODE_ENV` | No | `development` or `production`. Enables production-only checks. |

---

## Roadmap

See [docs/ROADMAP.md](docs/ROADMAP.md) for the full list of planned features.

---

## Contributing

Contributions are welcome and appreciated. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. All contributions must pass `flutter analyze` and the server TypeScript build without warnings.

---

## Security

Found a vulnerability? Please **do not open a public issue**. Instead, email the maintainers directly (contact details in the Security policy). See [docs/SECURITY.md](docs/SECURITY.md) for the full threat model and disclosure process.

---

## License

Chatly is released under the [MIT License](LICENSE). You are free to use, modify, and distribute this software — attribution is appreciated but not required.
