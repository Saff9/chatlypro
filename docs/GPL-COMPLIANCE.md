# GPL Compliance for Chatly

Chatly is a derivative of two GPL-licensed projects (Telegram-Android,
GPL-2.0+; TDesktop, GPL-3.0+). This document describes how we comply.

## 1. Source availability

The complete corresponding source for any Chatly binary is:

- This repository (overlay, patches, build scripts, CI configuration)
- The upstream repositories pinned in `apps/android/upstream.txt` and
  `apps/desktop/upstream.txt` at the recorded SHAs

Any Chatly release artifact (APK, AppImage, Windows zip) MUST link back to
this repo's commit SHA so users can reconstruct the exact source tree.
See `apps/*/build.sh` — the build embeds `GIT_SHA` into a resource file.

## 2. License notices

- Upstream license headers in source files are preserved unchanged.
- `LICENSE` at repo root inherits GPL-3.0-or-later.
- `NOTICE.md` lists upstream copyright holders.
- In-app "About Chatly" must show a link to this repo and to the upstream
  repos. This is enforced by the overlay file
  `apps/android/overlay/TMessagesProj/src/main/res/xml/about_chatly.xml`
  (TODO once Android build is verified) and the TDesktop equivalent.

## 3. Modifications

All Chatly modifications are recorded as files under `apps/*/overlay/`
and `apps/*/patches/`. No upstream file is modified silently; every
change is either a file in `overlay/` (full replacement) or a `.patch`
(diff).

## 4. Distribution

If you redistribute Chatly binaries, you MUST:

- Either include the corresponding source (this repo at the same commit SHA
  + the pinned upstream refs), OR
- Provide a written offer valid for at least three years to supply that
  source on request (GPL-3 §6).

The repository commit SHA used for any release is recorded in the
release's GitHub Actions run; do not delete those workflow runs.

## 5. What we do NOT inherit from Telegram

- Trademark rights to "Telegram" or the paper-plane logo — handled in NOTICE.md.
- Permission to use Telegram's API ID/Hash for clone clients — Chatly's
  API credentials are obtained separately from my.telegram.org under the
  project owner's account.
- Telegram's server-side infrastructure — Chatly clients still connect to
  Telegram's servers; if those servers refuse our API_ID, the apps stop
  working. This is not a GPL question but a deployment risk.
