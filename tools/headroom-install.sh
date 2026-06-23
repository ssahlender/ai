#!/usr/bin/env bash
# Installs Headroom — context compression layer for AI agents.
# Uses uv (PyPI package headroom-ai[proxy]).
# Provides: headroom CLI, proxy server, MCP tools, ONNX Kompress text compression.
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_uv-wrapper.sh"

ensure_uv_or_pipx

UV="$(find_uv)"

# On i9 the corporate proxy uses a custom CA — uv must see the system bundle
[ -n "${IS_I9:-}" ] && export SSL_CERT_FILE="${SYSTEM_CA_FILE}"

echo "Installing headroom-ai[proxy] via uv..."
"$UV" tool install "headroom-ai[proxy]"

# Verify
HEADROOM_BIN="$HOME/.local/bin/headroom"
if [ ! -x "$HEADROOM_BIN" ]; then
  HEADROOM_BIN="$("$UV" tool dir)/headroom/bin/headroom"
fi

if [ -x "$HEADROOM_BIN" ]; then
  echo "headroom installed: $HEADROOM_BIN"
  "$HEADROOM_BIN" --version
else
  echo "ERROR: headroom binary not found after install" >&2
  exit 1
fi

echo "headroom-ai[proxy] installed successfully."
echo "Run 'headroom-init.sh' to configure the proxy service."
