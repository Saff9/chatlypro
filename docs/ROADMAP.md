# Chatly Roadmap

## Phase 0 — Scaffolding (this PR)

- [x] Move legacy portfolio site to `web/`
- [x] Untrack `node_modules/` and `.next/` (was committed by mistake)
- [x] Create overlay/patch directory structure for Android + Desktop
- [x] Pin upstream refs in `upstream.txt`
- [x] `build.sh` scripts that fetch upstream, apply overlay, build
- [x] GitHub Actions: Android debug APK, Desktop Linux AppImage,
      Desktop Windows portable
- [x] GPL/license/attribution docs

## Phase 1 — Working unsigned debug builds

- [ ] Obtain `TELEGRAM_API_ID`/`TELEGRAM_API_HASH` from my.telegram.org
      and add as GitHub repo secrets
- [ ] CI green on `android.yml` — APK installs and launches on a real device
      (will show "API_ID invalid" until Phase 1 secrets are in)
- [ ] CI green on `desktop-linux.yml` — AppImage launches on Ubuntu 22.04+
- [ ] CI green on `desktop-windows.yml` — portable build launches on Win 10/11

## Phase 2 — Minimal Chatly rebrand

- [ ] App name "Chatly" everywhere (settings header, notifications, splash)
- [ ] Chatly launcher icon (Android adaptive + Desktop .ico/.icns/.png)
- [ ] Replace splash artwork (Telegram paper plane is trademarked)
- [ ] Color scheme override (current Telegram blue → Chatly palette)
- [ ] In-app "About Chatly" screen linking to this repo per GPL §3
- [ ] Package id / application id: `com.chatly.messenger` (Android),
      `org.chatly.Chatly` (Linux desktop), Chatly product GUID (Windows)

## Phase 3 — Production hardening

- [ ] Strip Telegram-Premium / paid features that depend on Telegram's
      payment backend (or accept that they appear broken)
- [ ] Disable Google Play Services-only code paths if building open-source
      flavor (`afatStandalone` vs `afatRelease`)
- [ ] Set up automatic upstream-sync workflow (weekly PR with rebased patches)
- [ ] Document threat model & known-not-fixed CVE policy

## Phase 4 — Signing & distribution (requires user credentials)

- [ ] Android: generate release keystore, configure CI to sign release APK + AAB
- [ ] Windows: code-signing cert, sign portable + add NSIS installer
- [ ] Linux: optional .deb / .rpm / flatpak / snap
- [ ] Auto-update channel (Android: in-app, Desktop: built-in updater)
- [ ] Crash reporting (Sentry self-hosted, not Telegram's)

## Phase 5 — Optional "real backend" path

If at any point Telegram revokes our API_ID (their policy explicitly bans
clones), or if you want true ownership of the data:

- Run TDLib against our own server stack, or
- Migrate to a different protocol (Matrix, Signal Protocol on top of XMPP, etc.)

That is a much larger project and is tracked separately from this fork.
