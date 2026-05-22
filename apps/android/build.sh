#!/usr/bin/env bash
# Chatly Android build script.
#
# Usage:
#   ./apps/android/build.sh [debug|release]
#
# Required env vars:
#   TELEGRAM_API_ID    — numeric ID from my.telegram.org
#   TELEGRAM_API_HASH  — 32-char hex string from my.telegram.org
#
# Optional env vars:
#   UPSTREAM_DIR       — where to clone/cache upstream (default: ./upstream-cache/telegram-android)
#   OUTPUT_DIR         — where built APK lands (default: ./apps/android/out)
#   ANDROID_HOME       — Android SDK location (required; CI sets this)

set -euo pipefail

BUILD_TYPE="${1:-debug}"
if [[ "$BUILD_TYPE" != "debug" && "$BUILD_TYPE" != "release" ]]; then
  echo "ERROR: build type must be 'debug' or 'release', got '$BUILD_TYPE'" >&2
  exit 64
fi

# Resolve absolute paths.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
UPSTREAM_DIR="${UPSTREAM_DIR:-$REPO_ROOT/upstream-cache/telegram-android}"
OUTPUT_DIR="${OUTPUT_DIR:-$HERE/out}"

# Read pinned upstream from upstream.txt (skip comment lines).
PIN_LINE="$(grep -v '^[[:space:]]*#' "$HERE/upstream.txt" | grep -v '^[[:space:]]*$' | head -n1)"
UPSTREAM_URL="$(echo "$PIN_LINE" | awk '{print $1}')"
UPSTREAM_REF="$(echo "$PIN_LINE" | awk '{print $2}')"

echo "=========================================================="
echo "Chatly Android build"
echo "  build type:   $BUILD_TYPE"
echo "  upstream:     $UPSTREAM_URL @ $UPSTREAM_REF"
echo "  upstream dir: $UPSTREAM_DIR"
echo "  output dir:   $OUTPUT_DIR"
echo "=========================================================="

if [[ -z "${TELEGRAM_API_ID:-}" || -z "${TELEGRAM_API_HASH:-}" ]]; then
  echo "ERROR: TELEGRAM_API_ID and TELEGRAM_API_HASH must be set." >&2
  echo "Get them from https://my.telegram.org → API development tools." >&2
  exit 65
fi

if [[ -z "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}" ]]; then
  echo "ERROR: ANDROID_HOME (or ANDROID_SDK_ROOT) must point at an Android SDK." >&2
  exit 66
fi

# 1) Clone or update upstream at the pinned ref.
mkdir -p "$(dirname "$UPSTREAM_DIR")"
if [[ ! -d "$UPSTREAM_DIR/.git" ]]; then
  echo "[1/5] Cloning upstream Telegram-Android..."
  git clone --depth 1 --branch "$UPSTREAM_REF" --recurse-submodules --shallow-submodules \
    "$UPSTREAM_URL" "$UPSTREAM_DIR"
else
  echo "[1/5] Updating upstream cache to $UPSTREAM_REF..."
  git -C "$UPSTREAM_DIR" fetch --depth 1 origin "refs/tags/$UPSTREAM_REF:refs/tags/$UPSTREAM_REF" || true
  git -C "$UPSTREAM_DIR" checkout -f "$UPSTREAM_REF"
  git -C "$UPSTREAM_DIR" submodule update --init --recursive --depth 1
  git -C "$UPSTREAM_DIR" clean -fdx -- ':!gradle' ':!.gradle'
fi

# 2) Copy overlay tree over upstream.
echo "[2/5] Applying Chatly overlay..."
if [[ -d "$HERE/overlay" ]]; then
  # cp -R is intentionally tolerant of empty overlay (initial scaffolding).
  if [[ -n "$(ls -A "$HERE/overlay" 2>/dev/null)" ]]; then
    cp -R "$HERE/overlay/." "$UPSTREAM_DIR/"
  else
    echo "  (overlay directory is empty — skipping)"
  fi
else
  echo "  (no overlay directory — skipping)"
fi

# 3) Apply patches in lexical order.
echo "[3/5] Applying Chatly patches..."
if [[ -d "$HERE/patches" ]]; then
  shopt -s nullglob
  for p in "$HERE/patches"/*.patch; do
    echo "  applying $(basename "$p")"
    git -C "$UPSTREAM_DIR" apply --whitespace=nowarn "$p"
  done
  shopt -u nullglob
else
  echo "  (no patches/ directory — skipping)"
fi

# 4) Inject API credentials.
#    Telegram-Android historically reads these from BuildVars.java; we sed-patch
#    in place so we never persist real secrets to disk in any repo.
echo "[4/5] Injecting API credentials..."
BUILDVARS="$UPSTREAM_DIR/TMessagesProj/src/main/java/org/telegram/messenger/BuildVars.java"
if [[ -f "$BUILDVARS" ]]; then
  # Match common variants of the constant declarations; if upstream renames them
  # we'll detect the failure via the build, not silently ship placeholders.
  python3 - "$BUILDVARS" "$TELEGRAM_API_ID" "$TELEGRAM_API_HASH" <<'PY'
import re, sys
path, api_id, api_hash = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, 'r', encoding='utf-8') as f:
    s = f.read()
orig = s
s = re.sub(r'(public\s+static\s+(?:final\s+)?int\s+APP_ID\s*=\s*)\d+',
           rf'\g<1>{api_id}', s)
s = re.sub(r'(public\s+static\s+(?:final\s+)?String\s+APP_HASH\s*=\s*")[^"]*(")',
           rf'\g<1>{api_hash}\g<2>', s)
if s == orig:
    print(f"WARNING: could not patch APP_ID/APP_HASH in {path}", file=sys.stderr)
    sys.exit(2)
with open(path, 'w', encoding='utf-8') as f:
    f.write(s)
print(f"OK patched {path}")
PY
else
  echo "  WARNING: BuildVars.java not found at expected location."
  echo "  Upstream may have restructured. Build will likely fail; please update build.sh."
fi

# 5) Build.
echo "[5/5] Running Gradle..."
cd "$UPSTREAM_DIR"

# Pick the most generic flavor that does NOT require Google Play Services or
# the AppCenter / push-keystore extras. afat = all ABIs, Standalone = no GMS.
case "$BUILD_TYPE" in
  debug)   GRADLE_TASKS=( ":TMessagesProj_App:assembleAfatStandaloneDebug" ) ;;
  release) GRADLE_TASKS=( ":TMessagesProj_App:assembleAfatStandaloneRelease" ) ;;
esac

chmod +x ./gradlew
./gradlew --no-daemon --stacktrace "${GRADLE_TASKS[@]}"

# Collect output.
mkdir -p "$OUTPUT_DIR"
find "$UPSTREAM_DIR/TMessagesProj_App/build/outputs/apk" -name '*.apk' -print0 \
  | xargs -0 -I {} cp -v {} "$OUTPUT_DIR/"
echo
echo "Build done. APKs in: $OUTPUT_DIR"
ls -la "$OUTPUT_DIR"
