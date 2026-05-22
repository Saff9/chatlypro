# Senior-Dev Security Review — Chatly (Telegram fork direction)

This document captures the honest pre-flight review of the security
implications of forking Telegram's clients and shipping them as "Chatly".

## TL;DR

Forking Telegram-Android + TDesktop and shipping under a new brand gives
you the **same** security properties as upstream Telegram — neither
better nor worse — **for as long as Telegram allows your API_ID to
connect to their servers**. It does NOT give you ownership of the
network or the data. If you tell users "this is more secure than
Telegram", that statement is false.

## What you actually get from this approach

| Property                     | Inherited?  | Notes                                              |
|------------------------------|-------------|----------------------------------------------------|
| MTProto 2.0 transport crypto | Yes         | Implemented in upstream client + server            |
| Cloud chat encryption        | Yes (server-side) | Server can read your messages; not E2E       |
| Secret-Chat E2E (Diffie-Hellman) | Yes     | Limited to 1-1, no sync across devices             |
| 2FA / cloud password         | Yes         | Standard upstream feature                          |
| Local message DB encryption  | Yes (passcode mode) | Standard upstream feature                    |
| Self-destructing messages    | Yes         | Standard upstream feature                          |
| Voice/Video calls (E2E)      | Yes         | Standard upstream feature                          |

## What you do NOT get

1. **No control over the server.** Every cloud message goes through
   Telegram's servers in unencrypted-at-rest form. Telegram can read,
   subpoena, and shut down accounts. Your "Chatly" branding doesn't change this.

2. **API_ID revocation risk.** Telegram's terms forbid clones of
   official apps. They have revoked API_IDs of well-known forks in the
   past (e.g. multiple unofficial clients have hit this). On revocation,
   every Chatly installation simultaneously stops being able to log in.
   This is a single point of failure outside your control.

3. **Trademark risk.** "Telegram" and the paper-plane logo are
   registered trademarks of Telegram FZ-LLC. Even with a complete name
   change to "Chatly", any residual artwork from upstream that is
   trademarked must be replaced. The overlay layer in this repo is
   structured to enforce this.

4. **Supply-chain risk.** Each upstream pull brings ~1M lines of new
   code with whatever vulnerabilities upstream has. Chatly's build
   pipeline must track upstream security advisories and ship promptly.

5. **No claim to "end-to-end security like Signal".** Telegram's
   cloud chats are *not* E2E by default. Only Secret Chats are. If
   you market Chatly as "E2E by default", that is incorrect.

## Hardening that IS in scope for this repo (Phase 2+)

- Disable proprietary push integrations (FCM/HMS) where possible so
  notifications don't route through Google/Huawei when you don't need them.
- Strip / disable Telegram-Premium-only features so users aren't shown
  paywalls for things that won't work for them.
- Enable `DESKTOP_APP_DISABLE_AUTOUPDATE=ON` for TDesktop builds — you
  do NOT want the official Telegram updater silently replacing your
  rebranded client with the official one (the build scripts already do this).
- Enable `DESKTOP_APP_DISABLE_CRASH_REPORTS=ON` — crash reports go to
  Telegram's servers by default; you don't want your users' crash
  payloads leaking there.
- Configurable connection settings (proxy, custom DC, TON proxy) are
  in upstream — surface them in onboarding.
- Compile with the latest stable upstream tag, not master; pin via
  `apps/*/upstream.txt`.

## Hardening that requires an actual server (Phase 5)

If you want any of the following, this fork is the wrong shape and you
need a real backend:

- "Only I and the recipient can read this" guarantee for ALL chats (not
  just Secret Chats).
- Resistance to API_ID revocation by Telegram.
- GDPR data-controller status under your own legal entity.
- Self-hostable / on-premise deployment.

A reasonable Phase 5 architecture would be:

```
Chatly Android (this fork, talking to → )  
Chatly Desktop (this fork, talking to → )  
                                                                                                                                          ┐
                                                                                                                                          ├── Chatly Server (TDLib-as-a-library OR Matrix OR custom MTProto-compatible)
                                                                                                                                          ┘
```

That is many sessions of additional work and out of scope for the
current PR.

## Reviewer notes for this PR

What this PR does:

- Establishes a clean overlay/patch fork structure (no giant submodules).
- Pins upstream to a recent stable tag.
- Sets up CI to produce unsigned debug builds on every push.
- Adds explicit GPL compliance and trademark documentation.
- Wipes the previous committed `node_modules/` and `.next/` directories.

What this PR does NOT do:

- Does not ship a working APK yet — the build will likely need 1-3
  CI iterations to converge on the right Gradle flavor / NDK pin.
- Does not yet apply any Chatly branding to the upstream UI (overlay
  directories are empty placeholders).
- Does not configure release signing.
- Does not run any tests because there are no tests yet.
