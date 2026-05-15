#!/usr/bin/env bash
set -euo pipefail

if ! command -v context-mode >/dev/null 2>&1; then
  echo "context-mode is not installed. Run ./context-mode-install.sh first."
  exit 1
fi

if command -v claude >/dev/null 2>&1; then
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
  echo "claude not found — skipping Claude Code context-mode plugin"
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
  python3 - <<'PY'
import json
import os
from pathlib import Path

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
data.setdefault("mcp", {})["context-mode"] = {
    "type": "local",
    "command": ["context-mode"],
    "enabled": True,
}

config_path.write_text(json.dumps(data, indent=2) + "\n")
print(f"OpenCode context-mode MCP configured in {config_path}")
PY
else
  echo "python3 not found — skipping OpenCode context-mode config"
fi
