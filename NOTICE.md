# NOTICE

Chatly is a derivative work of two upstream open-source projects:

## Telegram-Android
- Upstream: https://github.com/DrKLO/Telegram
- License: **GPL-2.0-or-later**
- Copyright © Telegram Messenger Inc. and contributors

## Telegram Desktop (TDesktop)
- Upstream: https://github.com/telegramdesktop/tdesktop
- License: **GPL-3.0-or-later**
- Copyright © 2014-2025 The Telegram Desktop Authors

In accordance with the GPL:

1. The full source of every binary distributed under the Chatly name is
   available in this repository, including the unmodified upstream sources
   (fetched at the refs pinned in `apps/*/upstream.txt`) and our overlay,
   patches, and build scripts.
2. Chatly binaries are distributed under the same GPL terms as upstream.
   See [`LICENSE`](LICENSE).
3. Upstream copyright notices in source files are preserved as-is.
4. Modifications introduced by Chatly are recorded as:
   - `apps/*/overlay/` — files that replace upstream files at build time
   - `apps/*/patches/` — diffs applied at build time
   - The Chatly project commit history in this repo

## Trademarks (NOT licensed to us)

- "Telegram", the Telegram paper-plane logo, the "TDesktop" name and any
  associated wordmarks/figurative marks are trademarks of **Telegram FZ-LLC**.
- Chatly does not use these marks in distributed builds. Our overlay
  replaces them with Chatly branding.
- If you fork Chatly, you must replace Chatly's branding too — Chatly
  branding is not licensed for redistribution under your own product name.

## API credentials

Chatly builds require a Telegram API ID/Hash obtained from
<https://my.telegram.org>. These credentials are personal to the Chatly
project owner and are injected as build-time secrets — they are NOT
committed to this repository.

## Reporting

If you believe Chatly violates a copyright or trademark, open an issue
or contact the repository owner.
