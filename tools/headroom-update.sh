#!/usr/bin/env bash
# Upgrades Headroom to latest version via uv.
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_uv-wrapper.sh"

UV="$(find_uv)" || { echo "uv not found — cannot upgrade headroom" >&2; exit 1; }

echo "Upgrading headroom-ai[proxy] via uv..."
"$UV" tool upgrade headroom-ai 2>&1 || {
  # upgrade may fail if not installed — fall back to install
  echo "upgrade failed — trying install"
  "$UV" tool install "headroom-ai[proxy]"
}

HEADROOM_BIN="$HOME/.local/bin/headroom"
[ -x "$HEADROOM_BIN" ] || HEADROOM_BIN=$("$UV" tool dir)/headroom/bin/headroom

if [ -x "$HEADROOM_BIN" ]; then
  echo "headroom updated: $("$HEADROOM_BIN" --version 2>&1)"
else
  echo "WARNING: headroom binary not found after upgrade" >&2
fi
