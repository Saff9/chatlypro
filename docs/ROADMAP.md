# Chatly — Product Roadmap

This document outlines confirmed upcoming features, listed in rough priority order.
Each item includes a brief technical description and the user-facing benefit.

Contributions toward any of these milestones are welcome. See [CONTRIBUTING.md](../CONTRIBUTING.md)
for guidelines on opening feature pull requests.

---

## Version 1.1 — Stability & Performance

### Multi-Device Session Sync
- **Status**: Planned
- Each device maintains an independent E2E key chain. The server facilitates
  encrypted key bundles so new devices can receive historical messages from
  other verified devices via a one-time handshake. No plaintext leaves the device.
- **User benefit**: Continue conversations seamlessly from a new phone or tablet
  without losing history.

### Biometric Vault Unlock
- **Status**: Planned
- Bind the local Hive AES-256 encryption key derivation to the device's
  Face ID / fingerprint sensor via the platform `LocalAuthentication` API.
  PIN fallback is retained.
- **User benefit**: Open the app in one tap without typing a PIN, with the same
  security level as device-native authentication.

### Improved Offline Sync
- **Status**: Planned
- Smarter offline outbox queue with message deduplication, exponential
  back-off on reconnect, and delivery receipts tied to actual server acknowledgement
  rather than optimistic local writes.
- **User benefit**: Messages sent during a network dropout are reliably delivered
  when connectivity resumes, with accurate sent/delivered status.

---

## Version 1.2 — Calls & Rich Media

### Voice & Video Calls (WebRTC E2E)
- **Status**: Planned
- Peer-to-peer WebRTC calls with DTLS-SRTP media encryption. The relay
  server acts as a STUN/TURN coordinator only — no media passes through
  the Chatly infrastructure.
- **User benefit**: Free, fully encrypted one-to-one voice and video calls
  with no call logs stored anywhere.

### Message Scheduling
- **Status**: Planned
- Queue messages to send at a future UTC timestamp. Stored in the local
  Hive outbox with a background isolate that monitors the clock and
  dispatches when the threshold is reached.
- **User benefit**: Send a morning greeting without waking up early, or
  deliver a reminder at precisely the right moment.

### Chatly Stories / Status
- **Status**: Planned
- 24-hour ephemeral media posts visible only to verified contacts. Stories
  are E2E encrypted individually per viewer, expire automatically, and are
  never stored on the relay server.
- **User benefit**: Share moments with trusted contacts without the permanent
  record that traditional social platforms create.

---

## Version 1.3 — Privacy Hardening

### Tor / Onion Mode
- **Status**: Research
- Route all traffic through the Tor network by bundling a lightweight Tor
  SOCKS5 proxy layer within the app. Users can toggle this in Privacy Settings.
- **User benefit**: Mask the server IP address from network-level observers,
  making it impossible for an ISP or network administrator to detect that
  Chatly is being used.

### UnifiedPush Support
- **Status**: Planned
- Replace Firebase Cloud Messaging (FCM) with UnifiedPush, an open standard
  supported by self-hosted push providers (Ntfy, Gotify). This enables
  fully de-Googled Android builds for F-Droid distribution.
- **User benefit**: Receive push notifications without any Google service
  dependency, suitable for GrapheneOS and CalyxOS users.

### Self-Hosted Server Mode
- **Status**: Planned
- A single `docker-compose.yml` that spins up the Fastify relay, PostgreSQL,
  Redis, and the ML service in one command. Includes a guided setup wizard
  in the app for pointing the client at a custom server URL.
- **User benefit**: Full data sovereignty — your messages relay through a
  server you control, on hardware you own.

---

## Version 1.4 — AI & Intelligence

### On-Device AI Smart Replies
- **Status**: Research
- An optional on-device LLM (Gemma 2B or LLaVA) running via the
  `flutter_llama` or ONNX Runtime bindings. Suggests reply drafts
  without any data leaving the device.
- **User benefit**: Contextual reply suggestions with zero cloud
  exposure — the model runs entirely locally on the device's NPU/GPU.

### Bluetooth Mesh Messaging
- **Status**: Research
- Extend the existing P2P mesh over Bluetooth LE for truly zero-network
  messaging between devices within BLE range. Implements a store-and-forward
  relay via intermediary devices in the mesh.
- **User benefit**: Send messages in locations with no internet — underground,
  at festivals, in remote areas.

---

## Version 1.5 — Community & Content

### Community Channels
- **Status**: Planned
- Broadcast-style channels where admins post to a subscriber list.
  Messages are encrypted with a per-channel symmetric key distributed
  to subscribers via the existing key exchange infrastructure.
  Subscriber cap and invite-only access controls included.
- **User benefit**: Follow trusted sources or communities without
  exposing your identity to other subscribers.

### Custom Sticker Packs
- **Status**: Planned
- Import WebP sticker packs from a ZIP file or create them in-app
  from photos. Packs are stored locally; sharing happens peer-to-peer
  with no CDN or external asset hosting.
- **User benefit**: Expressive, personalized communication without
  giving a third-party sticker marketplace access to usage data.

---

## Long-Term Vision

- **Decentralized Identity** — DID (Decentralized Identifier) support
  so usernames are self-sovereign and not tied to any Chatly server.
- **Desktop Clients** — Native macOS and Linux apps with full feature parity.
- **Hardware Security Key (FIDO2)** — YubiKey / WebAuthn second factor
  for the highest-security accounts.
- **Satellite / LoRa Fallback** — Integration with Meshtastic or similar
  LoRa mesh radios for messaging in truly off-grid environments.
