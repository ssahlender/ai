#!/usr/bin/env bash
# Upgrades Headroom to latest version via uv. Skips if not installed.
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_uv-wrapper.sh"

if ! command -v headroom >/dev/null 2>&1; then
  echo "headroom not installed — skipping"
  exit 0
fi

UV="$(find_uv)" || { echo "uv not found — cannot upgrade headroom" >&2; exit 1; }

# On i9 the corporate proxy uses a custom CA — uv must see the system bundle
[ -n "${IS_I9:-}" ] && export SSL_CERT_FILE="${SYSTEM_CA_FILE}"

echo "Upgrading headroom-ai[proxy] via uv..."
"$UV" tool upgrade headroom-ai

HEADROOM_BIN="$HOME/.local/bin/headroom"
[ -x "$HEADROOM_BIN" ] || HEADROOM_BIN="$("$UV" tool dir)/headroom/bin/headroom"

if [ -x "$HEADROOM_BIN" ]; then
  echo "headroom updated: $("$HEADROOM_BIN" --version 2>&1)"
else
  echo "WARNING: headroom binary not found after upgrade" >&2
fi
