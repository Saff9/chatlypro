# Contributing to Chatly

Thank you for taking an interest in contributing to Chatly. All contributions
— bug reports, feature requests, documentation improvements, and pull requests —
are genuinely appreciated.

---

## Getting Started

1. **Fork** the repository on GitHub.
2. **Clone** your fork and follow the setup in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).
3. Create a **feature branch**: `git checkout -b feature/your-feature-name`
4. Make your changes and **commit** with a clear, concise message:
   `git commit -m "feat: add biometric unlock for vault chats"`
5. Push the branch and open a **Pull Request** against `main`.

---

## Commit Message Format

Follow the conventional commit format:

```
<type>(<scope>): <description>

Types: feat | fix | docs | style | refactor | test | chore
```

Examples:
- `feat(auth): add TOTP-based 2FA toggle`
- `fix(chat): correct message timestamp timezone offset`
- `docs(readme): add Railway deploy button`

---

## Code Standards

- **Flutter/Dart**: Run `flutter analyze` before opening a PR. Zero warnings required.
- **TypeScript**: Run `npm run build` in `packages/chatly-server`. Zero errors.
- **Comments**: Write comments in plain English as you would explain to a teammate.
  Avoid stating what the code obviously does — explain *why* it does it.
- **No Placeholders**: Remove any TODO comments or placeholder data before merging.
- **Secrets**: Never commit `.env` files, API keys, or signing keystores.

---

## Reporting Bugs

Open a GitHub issue using the Bug Report template. Include:
- Flutter/Dart version (`flutter --version`)
- OS and device/emulator details
- Steps to reproduce
- Expected vs. actual behavior
- Relevant error output or stack trace

---

## Security Vulnerabilities

**Do not open a public GitHub issue for security vulnerabilities.**
See [docs/SECURITY.md](docs/SECURITY.md) for the responsible disclosure process.

---

## License

By contributing, you agree that your contributions will be licensed under the
same [MIT License](LICENSE) that covers the project.
