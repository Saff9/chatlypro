#!/usr/bin/env bash
# Chatly Desktop (Linux) build script.
#
# Uses TDesktop's official Docker build image. Produces an AppImage.
#
# Required env vars:
#   TELEGRAM_API_ID
#   TELEGRAM_API_HASH
#
# Optional env vars:
#   UPSTREAM_DIR       — where to clone upstream (default: ./upstream-cache/tdesktop)
#   OUTPUT_DIR         — where build artifact lands (default: ./apps/desktop/out)
#   TDESKTOP_BUILD_IMG — docker image to use (default: upstream centos_env image)
#   BUILD_JOBS         — parallel jobs (default: nproc)

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
UPSTREAM_DIR="${UPSTREAM_DIR:-$REPO_ROOT/upstream-cache/tdesktop}"
OUTPUT_DIR="${OUTPUT_DIR:-$HERE/out}"
BUILD_JOBS="${BUILD_JOBS:-$(nproc 2>/dev/null || echo 2)}"

PIN_LINE="$(grep -v '^[[:space:]]*#' "$HERE/upstream.txt" | grep -v '^[[:space:]]*$' | head -n1)"
UPSTREAM_URL="$(echo "$PIN_LINE" | awk '{print $1}')"
UPSTREAM_REF="$(echo "$PIN_LINE" | awk '{print $2}')"

echo "=========================================================="
echo "Chatly Desktop (Linux) build"
echo "  upstream:     $UPSTREAM_URL @ $UPSTREAM_REF"
echo "  upstream dir: $UPSTREAM_DIR"
echo "  output dir:   $OUTPUT_DIR"
echo "  jobs:         $BUILD_JOBS"
echo "=========================================================="

if [[ -z "${TELEGRAM_API_ID:-}" || -z "${TELEGRAM_API_HASH:-}" ]]; then
  echo "ERROR: TELEGRAM_API_ID and TELEGRAM_API_HASH must be set." >&2
  exit 65
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker is required for the Linux desktop build." >&2
  exit 66
fi

# 1) Clone upstream.
if [[ ! -d "$UPSTREAM_DIR/.git" ]]; then
  echo "[1/4] Cloning upstream TDesktop..."
  git clone --depth 1 --branch "$UPSTREAM_REF" --recurse-submodules --shallow-submodules \
    "$UPSTREAM_URL" "$UPSTREAM_DIR"
else
  echo "[1/4] Updating upstream cache to $UPSTREAM_REF..."
  git -C "$UPSTREAM_DIR" fetch --depth 1 origin "refs/tags/$UPSTREAM_REF:refs/tags/$UPSTREAM_REF" || true
  git -C "$UPSTREAM_DIR" checkout -f "$UPSTREAM_REF"
  git -C "$UPSTREAM_DIR" submodule update --init --recursive --depth 1
fi

# 2) Apply overlay.
echo "[2/4] Applying Chatly overlay..."
if [[ -d "$HERE/overlay" && -n "$(ls -A "$HERE/overlay" 2>/dev/null)" ]]; then
  cp -R "$HERE/overlay/." "$UPSTREAM_DIR/"
else
  echo "  (no overlay — skipping)"
fi

# 3) Apply patches.
echo "[3/4] Applying Chatly patches..."
if [[ -d "$HERE/patches" ]]; then
  shopt -s nullglob
  for p in "$HERE/patches"/*.patch; do
    echo "  applying $(basename "$p")"
    git -C "$UPSTREAM_DIR" apply --whitespace=nowarn "$p"
  done
  shopt -u nullglob
fi

# 4) Build inside the upstream's official container.
echo "[4/4] Building inside upstream Docker image..."

# TDesktop's official build image. If this tag disappears upstream, override
# via TDESKTOP_BUILD_IMG.
TDESKTOP_BUILD_IMG="${TDESKTOP_BUILD_IMG:-tdesktop/centos_env:latest}"

mkdir -p "$OUTPUT_DIR"

docker run --rm \
  -v "$UPSTREAM_DIR":/usr/src/tdesktop \
  -v "$OUTPUT_DIR":/usr/src/tdesktop/out/Release \
  -e API_ID="$TELEGRAM_API_ID" \
  -e API_HASH="$TELEGRAM_API_HASH" \
  -e BUILD_JOBS="$BUILD_JOBS" \
  "$TDESKTOP_BUILD_IMG" \
  /bin/bash -c '
    set -euo pipefail
    cd /usr/src/tdesktop
    # Use upstream cmake configuration.
    cmake -B out/Release -GNinja \
      -DCMAKE_BUILD_TYPE=Release \
      -DTDESKTOP_API_ID="$API_ID" \
      -DTDESKTOP_API_HASH="$API_HASH" \
      -DDESKTOP_APP_DISABLE_AUTOUPDATE=ON \
      -DDESKTOP_APP_DISABLE_CRASH_REPORTS=ON
    cmake --build out/Release -j "${BUILD_JOBS:-2}"
  '

echo
echo "Build done. Binary in: $OUTPUT_DIR"
ls -la "$OUTPUT_DIR" || true
