# Chatly System Architecture 🏗️

This document describes the high-level architecture of Chatly, a premium, cross-platform, zero-trace messaging app built with security and metadata privacy at its core.

---

## 🗂️ Project Structure

Chatly is organized as a monorepo, separating client applications from server and machine learning relay nodes:

```
chatly/
├── apps/
│   └── mobile/          # Cross-platform Flutter Application (Android, iOS, Web, Desktop)
├── packages/
│   ├── chatly-server/   # Node.js + TypeScript Fastify server (REST & WebSocket gateway)
│   └── chatly-ml/       # Python FastAPI toxicity analysis microservice
├── .github/
│   └── workflows/       # CI pipelines for automated Flutter builds
└── docs/                # Architecture and security specifications
```

---

## 📱 Client Architecture (Flutter)

The client application is built with **Flutter (Dart)**, compiling natively to Android, iOS, Web, Windows, macOS, and Linux.

### Key Components:
1. **Presentation Layer (UI/UX)**:
   - Clean, modern Material 3 design system with custom premium gradients and dark mode support.
   - Screen flows managed reactively through **Riverpod 2.x**.
   - Ephemeral **Vault Chats** built using visual theme transforms (gold/amber contrast triggers) indicating self-destruct state.

2. **Security & Cryptography**:
   - **On-Device Key Generation**: Custom 256-bit Identity Key Pairs generated locally and stored inside Hive Encrypted Box.
   - **Double Ratchet Engine**: Pure Dart cryptographic engine running X25519 DH handshakes for E2E encryption. Ciphertexts are produced on-device; plain text never enters the network.

3. **Data Caching**:
   - Built on **Hive (NoSQL)**. Local databases are AES-256 encrypted using keys derived from user device hardware keychains.
   - Automated retention schedules prune local message records after 7 days by default.

---

## 🖥️ Backend Architecture (Fastify)

The server acts strictly as a **stateless relay gateway**. It coordinates client handshakes, online presence, and offline packet holds.

### Data Storage Strategy (Zero-Trace Policy):
- **Supabase (PostgreSQL)**: Handles account registry and metadata.
  - Stored: Bcrypt hashes of user emails, usernames, public pre-keys (for Signal handshakes), and group member listings.
  - **Not Stored**: Plaintext passwords, phone numbers, IP records, or chat messages.
- **Upstash (Redis)**: Manages real-time cache with Time-To-Live (TTL) expiries.
  - Stored: Online indicators (30s TTL), typing states (3s TTL), and undelivered encrypted packets (24h TTL).
  - **Zero-Trace Relay**: If the recipient is online, messages pass straight through the WebSocket pipeline in memory; they never touch disk. If offline, the encrypted packet is cached in Redis and permanently deleted the instant the recipient boots up and pulls the data.

---

## 🤖 Moderation & Machine Learning (FastAPI)

To protect the anonymous **Lucky Pulse** feed, Chatly leverages a separate, lightweight ML microservice:
- Implements a FastAPI interface checking text packets for extreme toxicity.
- Runs a local **Detoxify BERT model** (PyTorch) in production.
- Integrates a **regex blacklist fallback engine** for local development, allowing the entire backend stack to boot on developer machines with low RAM footprint.

---

## 🚀 Scaling to 1M+ Active Users

To scale Chatly's stateless backend to 1,000,000+ concurrent active WebSocket connections, the architecture is designed for horizontal scalability and optimized system throughput:

### 1. Reverse-Proxy & Sticky Load Balancing
- **Nginx / HAProxy Reverse Proxy**: Configured to handle SSL/TLS termination and distribute incoming REST and WebSocket requests across a cluster of server nodes.
- **Sticky Sessions / IP Hash**: Uses IP Hash load balancing to bind clients to specific backend node instances, avoiding unnecessary reconnection overhead while permitting clean connection failover.

### 2. Horizontal Clustering with Redis Pub/Sub
To allow multiple backend servers to coordinate client deliveries across independent nodes:
- **Redis Pub/Sub Layer**: Node A and Node B run concurrently. If Bob is connected to Node A and sends a message to Alice who is connected to Node B:
  1. Node A receives the payload and checks its local socket registry.
  2. Finding no socket for Alice, Node A publishes the envelope to a Redis channel (`user:relays`).
  3. Node B (and all other nodes) subscribes to `user:relays`. Node B receives the pub/sub event, verifies Alice is connected to its local registry, and pushes the ciphertext directly over the active socket connection.
  4. If Alice is offline, the node that received the message persists the encrypted payload in Redis with a 24h TTL.

```
[Client Bob] ────> [Server Node A] ──(Redis Pub/Sub)──> [Server Node B] ────> [Client Alice]
```

### 3. Connection & Kernel Optimizations
- **File Descriptor Limits**: Scale Linux system limits (`/etc/security/limits.conf`) to permit `fs.file-max = 2097152`, allowing each node worker to scale beyond the default 1024 open file descriptors to handle over 250,000 active TCP connections per server VM.
- **Node Cluster Mode**: Deploy the Fastify backend using PM2 in cluster mode to automatically bind a worker process to every CPU core, optimizing multi-threading.
- **Adaptive Heartbeats**: The client-side adaptive WebSocket heartbeat shifts from 15s to 60s when on mobile links. This drastically cuts idle socket traffic and prevents connection stampedes during mobile network transitions.

