# Contributing to Chatly

Thank you for taking the time to contribute. This guide covers everything needed to open a quality pull request.

---

## Before You Start

- **Security issues** — please do **not** open a public issue. Follow the process in [docs/SECURITY.md](docs/SECURITY.md).
- **New features** — open a discussion issue first so we can align on scope before writing code.
- **Bug fixes** — go ahead and open a PR directly. Linking the issue is appreciated but not required.

---

## Development Setup

### Prerequisites

| Tool | Version |
|---|---|
| [Node.js](https://nodejs.org) | 18 or newer |
| [Flutter SDK](https://flutter.dev/docs/get-started/install) | 3.x |
| PostgreSQL 14+ | Optional — server boots with in-memory fallback |

### Start the backend

```bash
cd packages/chatly-server
npm install
npm run dev          # listens on http://localhost:5000
```

### Run the Flutter client

```bash
cd apps/mobile
flutter pub get
flutter run -d chrome          # Web
flutter run -d windows         # Windows desktop
flutter run                    # Connected Android/iOS device
```

---

## Code Style

### Flutter / Dart

- Follow the [official Dart style guide](https://dart.dev/guides/language/effective-dart/style).
- Run `flutter analyze` — zero warnings before opening a PR.
- Comments should explain **why**, never **what**. Well-named identifiers already communicate what.
- Keep methods short. If a function exceeds ~60 lines, extract helpers.

### TypeScript (server)

- Run `npm run build` (TypeScript compile check) before pushing.
- Use `const` over `let` wherever the binding is not reassigned.
- Prefer `async`/`await` over raw Promise chains.
- All database queries must use parameterised placeholders (`$1`, `$2` …) — never string interpolation.

---

## Security Rules (non-negotiable)

1. **No plaintext message storage.** The server must never log or persist message content.
2. **Parameterised SQL only.** No string concatenation in queries.
3. **Validate all WebSocket inputs server-side** — size, type, membership.
4. **Never commit secrets.** Use environment variables; `.env` is git-ignored.
5. **Do not weaken E2E crypto.** Any change to `encryption_service.dart` or the key-exchange routes requires a reviewer with cryptography background.

---

## Pull Request Checklist

Before requesting review, confirm:

- [ ] `flutter analyze` passes with zero warnings.
- [ ] `npm run build` passes in `packages/chatly-server`.
- [ ] No debug `print()` or `console.log` statements left behind.
- [ ] Dead code removed (unused imports, commented-out blocks, unreachable branches).
- [ ] New REST routes have input validation and are guarded by the existing rate limiter.
- [ ] New Flutter screens are either wired into navigation or documented as modal-only.
- [ ] `README.md` / `CLAUDE.md` updated if you changed architecture, removed a feature, or added a new env variable.

---

## Commit Message Format

Follow the conventional commit format (72 chars max on the subject line):

```
<type>(<scope>): <short description>
```

| Type | When to use |
|---|---|
| `feat` | New user-visible behaviour |
| `fix` | Bug fix |
| `refactor` | Internal restructure with no behaviour change |
| `perf` | Performance improvement |
| `security` | Security hardening |
| `docs` | Documentation only |
| `chore` | Build scripts, CI, dependency bumps |

Examples:

```
fix(chat): clear typing indicator after 6 s timeout
feat(ws): add sent_ack event for reliable isSent confirmation
security(server): store group messages for offline members in Redis
```

---

## What Will Not Be Merged

- Re-adding removed features (Calculator disguise, Lucky Pulse, UDP proximity invite).
- Adding code back to `chat_screen.dart` that belongs in the `widgets/` layer — keep message rendering in `message_bubble.dart`, input in `chat_input_bar.dart`, and painters in `chat_painters.dart`.
- Dependencies with known high/critical CVEs.
- Changes that require a Python/ML microservice (out of scope for this repo).
- Any change that stores or logs plaintext messages on the server.
- Hardcoded secrets or fallback credentials in production code paths.

---

## Reporting Bugs

Open a GitHub issue with the Bug Report template. Include:

- Flutter/Dart version (`flutter --version`)
- OS and device/emulator details
- Steps to reproduce
- Expected vs. actual behaviour
- Relevant error output or stack trace

---

## License

By contributing, you agree that your contributions will be licensed under the same [MIT License](LICENSE) that covers the project.
