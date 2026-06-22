#!/usr/bin/env bash
# Installs Headroom MCP server integration for all supported agents.
# - Hermes Agent (mcp_servers in config.yaml)
# - Claude Code (headroom mcp install --agent claude)
# - Outputs config snippets for Codex / OpenCode / Pi
set -euo pipefail

HEADROOM_BIN="${HOME}/.local/bin/headroom"
PROXY_URL="${HEADROOM_PROXY_URL:-http://localhost:8788}"

if [ ! -x "$HEADROOM_BIN" ]; then
  echo "ERROR: headroom not found. Run headroom-install.sh first." >&2
  exit 1
fi

echo "=== Headroom MCP Integration ==="
echo "Binary:    $HEADROOM_BIN"
echo "Version:   $($HEADROOM_BIN --version 2>&1)"
echo "Proxy URL: $PROXY_URL"
echo ""

# --- 1. Hermes Agent ---
HERMES_CONFIG="${HOME}/.hermes/config.yaml"
if [ -f "$HERMES_CONFIG" ]; then
  if grep -q "headroom:" "$HERMES_CONFIG" 2>/dev/null; then
    echo "[Hermes] MCP config already present — skipping"
  else
    echo "[Hermes] Adding headroom MCP server to config.yaml..."
    # Careful YAML insertion at the end of mcp_servers block
    python3 -c "
import sys
with open('$HERMES_CONFIG', 'r') as f:
    lines = f.readlines()

# Find mcp_servers line and insert after last indented entry
insert_at = None
for i, line in enumerate(lines):
    if line.strip() == 'mcp_servers:':
        insert_at = i + 1
        break

if insert_at is None:
    # No mcp_servers section — append at end
    lines.append('\nmcp_servers:\n')
    lines.append('  headroom:\n')
    lines.append('    command: headroom\n')
    lines.append('    args: [mcp, serve]\n')
    lines.append('    timeout: 120\n')
else:
    # Insert headroom entry before next top-level key or end
    insert_idx = insert_at
    while insert_idx < len(lines) and (lines[insert_idx].startswith('  ') or lines[insert_idx].strip() == ''):
        insert_idx += 1
    new_entry = [
        '  headroom:\n',
        '    command: headroom\n',
        '    args: [mcp, serve]\n',
        '    timeout: 120\n',
    ]
    lines = lines[:insert_idx] + new_entry + lines[insert_idx:]

with open('$HERMES_CONFIG', 'w') as f:
    f.writelines(lines)
print('Done — Hermes will discover headroom MCP tools on next restart')
" 2>&1
  fi
else
  echo "[Hermes] No config.yaml found — skipping"
fi

# --- 2. Claude Code ---
echo ""
echo "[Claude Code] Installing MCP server..."
$HEADROOM_BIN mcp install --agent claude --proxy-url "$PROXY_URL" 2>&1 || {
  echo "WARNING: headroom mcp install failed for Claude Code"
  echo "  Manual config: add to ~/.claude/mcp.json:"
  echo '  {"mcpServers": {"headroom": {"command": "headroom", "args": ["mcp", "serve"]}}}'
}

# --- 3. Codex ---
echo ""
echo "[Codex] Not yet supported by headroom mcp install."
echo "  Manual config: add to ~/.codex/mcp.json:"
echo '  {"mcpServers": {"headroom": {"command": "headroom", "args": ["mcp", "serve"]}}}'

# --- 4. OpenCode ---
echo ""
echo "[OpenCode] Manual MCP config:"
echo "  Create ~/.config/opencode/mcp.json:"
echo '  {"mcpServers": {"headroom": {"command": "headroom", "args": ["mcp", "serve"]}}}'

# --- 5. Pi ---
echo ""
echo "[Pi] Manual MCP config:"
echo "  Add to your Pi MCP configuration:"
echo '  {"mcpServers": {"headroom": {"command": "headroom", "args": ["mcp", "serve"]}}}'

echo ""
echo "=== MCP Integration complete ==="
echo ""
echo "MCP tools available after agent restart:"
echo "  mcp_headroom_headroom_compress  — Compress text before sending to LLM"
echo "  mcp_headroom_headroom_retrieve  — Retrieve original from CCR cache"
echo "  mcp_headroom_headroom_stats     — Show compression statistics"
echo ""
echo "Hermes: restart required to discover new MCP tools."
echo "Claude/Codex/OpenCode/Pi: restart required."
