# Chatly

Chatly is a rebranded fork of the official Telegram open-source clients
([Telegram-Android](https://github.com/DrKLO/Telegram) and
[TDesktop](https://github.com/telegramdesktop/tdesktop)), packaged for Android,
Windows, and Linux.

> **Status:** scaffolding / unsigned debug builds. Production signing,
> store distribution, and trademark/branding asset replacement are tracked
> in [`docs/ROADMAP.md`](docs/ROADMAP.md).

---

## Repository layout

```
.
├── apps/
│   ├── android/           # Chatly Android client (overlay on Telegram-Android)
│   │   ├── overlay/       # files copied OVER upstream after `git clone`
│   │   ├── patches/       # *.patch files applied OVER upstream
│   │   ├── resources/     # Chatly icons, colors, strings
│   │   ├── upstream.txt   # pinned upstream git ref
│   │   └── build.sh       # clones upstream, applies overlay+patches, builds
│   └── desktop/           # Chatly desktop (overlay on TDesktop)
│       ├── overlay/
│       ├── patches/
│       ├── resources/
│       ├── upstream.txt
│       ├── build-linux.sh
│       └── build-windows.ps1
├── web/                   # legacy Next.js portfolio (preserved, not part of Chatly)
├── .github/workflows/     # CI for Android + Desktop builds
├── docs/                  # architecture, roadmap, GPL compliance notes
├── NOTICE.md              # upstream attribution & GPL compliance
└── LICENSE                # GPL terms inherited from upstream
```

We do **not** vendor the upstream source in this repo. Instead, every build
runs `apps/<platform>/build.sh`, which:

1. `git clone --depth 1` of the upstream repo at the pinned ref in `upstream.txt`
2. Copies files from `overlay/` over the working tree (replaces icons, strings,
   `BuildVars.java` style files, package id stubs, etc.)
3. Applies any `.patch` files in `patches/` in order
4. Injects build-time secrets (`TELEGRAM_API_ID`, `TELEGRAM_API_HASH`) from env
5. Invokes the upstream's normal build command

This keeps our repo tiny, makes upstream tracking trivial, and never
fights upstream's build system.

---

## Building

### Prerequisites

| Build         | Where it runs    | What you need                                                       |
|---------------|------------------|---------------------------------------------------------------------|
| Android APK   | Linux            | JDK 17, Android SDK + NDK (CI auto-installs), `TELEGRAM_API_ID/HASH` |
| Desktop Linux | Linux            | docker (uses upstream's official build container)                   |
| Desktop Win   | Windows          | Visual Studio 2022, Python, `TELEGRAM_API_ID/HASH`                  |

### Secrets

Both clients require `TELEGRAM_API_ID` and `TELEGRAM_API_HASH` from
<https://my.telegram.org> → API development tools. Without these, the apps
compile but crash on first network call.

In CI we read them from GitHub repository secrets of the same name.
For local builds export them in your shell before running `build.sh`:

```bash
export TELEGRAM_API_ID=12345
export TELEGRAM_API_HASH=0123456789abcdef0123456789abcdef
./apps/android/build.sh debug
```

### Local builds

```bash
# Android (debug APK, unsigned)
./apps/android/build.sh debug

# Desktop Linux (AppImage)
./apps/desktop/build-linux.sh

# Desktop Windows (run on a Windows host)
pwsh ./apps/desktop/build-windows.ps1
```

### CI

Pushes to any branch trigger three workflows:

- **android.yml** → produces `Chatly-debug.apk` artifact
- **desktop-linux.yml** → produces `Chatly-linux.AppImage` artifact
- **desktop-windows.yml** → produces `Chatly-windows-portable.zip` artifact

Download from the GitHub Actions run page.

---

## License & attribution

This project is a derivative work of upstream Telegram clients and is therefore
distributed under the **GNU General Public License**. Telegram-Android is
GPL-2.0+, TDesktop is GPL-3.0. See [`NOTICE.md`](NOTICE.md) and
[`docs/GPL-COMPLIANCE.md`](docs/GPL-COMPLIANCE.md).

The names "Telegram" and the Telegram paper-plane logo are trademarks of
**Telegram FZ-LLC**. Chatly does not use those names or marks in distributed
builds — see [`apps/*/overlay/`](apps) for the rebrand layer.

---

## Security review

Forking a Telegram client does **not** inherit Telegram's server-side security
guarantees. The MTProto encryption and the threat model around it depend on
talking to Telegram's servers with a Telegram-issued API_ID. If you ship Chatly
to real users:

- Telegram may revoke your API_ID under their "no clones of official apps" policy.
- All messages still flow through Telegram's servers — they can see metadata
  and (for cloud chats) message content. Only "Secret Chats" are E2E encrypted.
- You inherit the entire upstream attack surface; pull from upstream regularly.

For a security model that you actually control end-to-end, run your own backend
(TDLib + Telegram Server, or a different protocol). That is out of scope for
this repo's current direction.
