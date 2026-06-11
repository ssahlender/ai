#!/usr/bin/env bash
set -euo pipefail

# Include user-local bin in case npm installed there (e.g. on i9 with system npm)
export PATH="$HOME/.local/bin:$PATH"

if ! command -v context-mode >/dev/null 2>&1; then
  echo "context-mode is not installed. Run ./context-mode-install.sh first."
  exit 1
fi

if [ "${CONTEXT_MODE_ENABLE_CLAUDE:-0}" = "1" ] && command -v claude >/dev/null 2>&1; then
  if claude plugin marketplace list | grep -Eq 'context-mode|mksglu/context-mode'; then
    echo "Claude Code context-mode marketplace already configured"
  else
    claude plugin marketplace add mksglu/context-mode
  fi

  if claude plugin list | grep -Eq 'context-mode'; then
    claude plugin update context-mode
  else
    claude plugin install context-mode@context-mode
  fi
else
  echo "Claude Code context-mode plugin skipped. Set CONTEXT_MODE_ENABLE_CLAUDE=1 to enable it."
fi

if command -v codex >/dev/null 2>&1; then
  if codex mcp get context-mode >/dev/null 2>&1; then
    echo "Codex context-mode MCP already configured"
  else
    codex mcp add context-mode -- context-mode
  fi
else
  echo "codex not found — skipping Codex context-mode MCP"
fi

if command -v python3 >/dev/null 2>&1; then
  CONTEXT_MODE_ENABLE_OPENCODE="${CONTEXT_MODE_ENABLE_OPENCODE:-0}" python3 - <<'PY'
import json
import os
from pathlib import Path

enable_opencode = os.environ.get("CONTEXT_MODE_ENABLE_OPENCODE") == "1"
config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
config_path = config_home / "opencode" / "opencode.json"
config_path.parent.mkdir(parents=True, exist_ok=True)

if config_path.exists():
    try:
        data = json.loads(config_path.read_text())
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{config_path} is not valid JSON: {exc}")
else:
    data = {"$schema": "https://opencode.ai/config.json"}

data.setdefault("$schema", "https://opencode.ai/config.json")
if enable_opencode:
    data.setdefault("mcp", {})["context-mode"] = {
        "type": "local",
        "command": ["context-mode"],
        "enabled": True,
    }
    message = "OpenCode context-mode MCP configured"
else:
    if isinstance(data.get("mcp", {}).get("context-mode"), dict):
        data["mcp"]["context-mode"]["enabled"] = False
    message = "OpenCode context-mode MCP skipped. Set CONTEXT_MODE_ENABLE_OPENCODE=1 to enable it"

config_path.write_text(json.dumps(data, indent=2) + "\n")
print(f"{message} in {config_path}")
PY
else
  echo "python3 not found — skipping OpenCode context-mode config"
fi
