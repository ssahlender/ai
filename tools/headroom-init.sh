#!/usr/bin/env bash
# Initializes Headroom integration for AI coding tools.
# - Creates systemd user service for persistent proxy (port 8788)
# - Installs wrapper scripts for opencode/pi (claude/codex use 'headroom wrap')
# - Enables and starts the proxy service
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_uv-wrapper.sh"

HEADROOM_PORT="${HEADROOM_PORT:-8788}"
HEADROOM_PROXY_URL="http://localhost:${HEADROOM_PORT}"
WRAPPER_DIR="$HOME/.local/bin"

# Find headroom binary
HEADROOM_BIN=""
for candidate in "$HOME/.local/bin/headroom" "$HOME/.cargo/bin/headroom"; do
  if [ -x "$candidate" ]; then
    HEADROOM_BIN="$candidate"
    break
  fi
done
# fall back to uv tool dir
if [ -z "$HEADROOM_BIN" ]; then
  UV="$(find_uv 2>/dev/null)" || UV=""
  [ -n "$UV" ] && HEADROOM_BIN="$("$UV" tool dir 2>/dev/null)/headroom/bin/headroom" || true
fi

if [ ! -x "$HEADROOM_BIN" ]; then
  echo "ERROR: headroom binary not found. Run headroom-install.sh first." >&2
  exit 1
fi

echo "=== Headroom initialization ==="
echo "Binary:  $HEADROOM_BIN"
echo "Version: $("$HEADROOM_BIN" --version 2>&1)"
echo "Proxy port: ${HEADROOM_PORT}"
echo ""

# --- Systemd user service ---
SERVICE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
mkdir -p "$SERVICE_DIR"

cat > "$SERVICE_DIR/headroom-proxy.service" << SERVICEOF
[Unit]
Description=Headroom Proxy — context compression for AI agents
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${HEADROOM_BIN} proxy --port ${HEADROOM_PORT}
Restart=on-failure
RestartSec=5
Environment=HEADROOM_PORT=${HEADROOM_PORT}

[Install]
WantedBy=default.target
SERVICEOF

echo "systemd user service created: $SERVICE_DIR/headroom-proxy.service"

# --- Wrapper scripts for opencode + pi ---
# Claude Code + Codex use 'headroom wrap' (official integration).
# OpenCode + Pi are not in the wrap list — wrapper scripts set the proxy env var.

mkdir -p "$WRAPPER_DIR"

# headroom-opencode
cat > "$WRAPPER_DIR/headroom-opencode" << 'WRAPEOF'
#!/bin/bash
# Wrapper: OpenCode routed through Headroom proxy (port 8788)
export OPENAI_BASE_URL="http://localhost:8788/v1"
exec opencode "$@"
WRAPEOF
chmod +x "$WRAPPER_DIR/headroom-opencode"
echo "wrapper: $WRAPPER_DIR/headroom-opencode"

# headroom-pi
cat > "$WRAPPER_DIR/headroom-pi" << 'WRAPEOF'
#!/bin/bash
# Wrapper: Pi routed through Headroom proxy (port 8788)
export OPENAI_BASE_URL="http://localhost:8788/v1"
exec pi "$@"
WRAPEOF
chmod +x "$WRAPPER_DIR/headroom-pi"
echo "wrapper: $WRAPPER_DIR/headroom-pi"

echo ""
echo "To integrate Claude Code:   headroom wrap claude"
echo "To integrate Codex:         headroom wrap codex"
echo "To use OpenCode via proxy:  headroom-opencode"
echo "To use Pi via proxy:        headroom-pi"
echo ""

# Reload and enable
systemctl --user daemon-reload
systemctl --user enable headroom-proxy.service

echo "Starting proxy service..."
systemctl --user start headroom-proxy.service
for _i in {1..10}; do
  sleep 0.5
  if curl -sf --max-time 1 "${HEADROOM_PROXY_URL}/health" >/dev/null 2>&1; then
    echo "Proxy ready."
    break
  fi
done
systemctl --user status headroom-proxy.service --no-pager -l || true

echo ""
echo "=== Headroom initialization complete ==="
echo "Proxy running at ${HEADROOM_PROXY_URL}"
echo "Test: curl -s ${HEADROOM_PROXY_URL}/health"
