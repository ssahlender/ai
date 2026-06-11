#!/usr/bin/env bash
# Registers repomix MCP server with Claude Code, Codex, and OpenCode.
set -euo pipefail

# Include user-local bin in case repomix is installed there (e.g. on i9)
export PATH="$HOME/.local/bin:$PATH"

if ! command -v repomix >/dev/null 2>&1; then
  echo "repomix is not installed. Run ./repomix-install.sh first."
  exit 1
fi

# Claude Code — add repomix as MCP server in ~/.claude/settings.json
if command -v python3 >/dev/null 2>&1; then
  python3 - <<'PY'
import json
from pathlib import Path

settings_path = Path.home() / ".claude" / "settings.json"
settings_path.parent.mkdir(parents=True, exist_ok=True)
data = json.loads(settings_path.read_text()) if settings_path.exists() else {}

data.setdefault("mcpServers", {})["repomix"] = {
    "command": "repomix",
    "args": ["--mcp"],
}

settings_path.write_text(json.dumps(data, indent=2) + "\n")
print(f"Claude Code repomix MCP configured in {settings_path}")
PY
else
  echo "python3 not found — skipping Claude Code repomix MCP"
fi

# Codex
if command -v codex >/dev/null 2>&1; then
  if codex mcp get repomix >/dev/null 2>&1; then
    echo "Codex repomix MCP already configured"
  else
    codex mcp add repomix -- repomix --mcp
  fi
else
  echo "codex not found — skipping Codex repomix MCP"
fi

# OpenCode
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
data.setdefault("mcp", {})["repomix"] = {
    "type": "local",
    "command": ["repomix", "--mcp"],
    "enabled": True,
}

config_path.write_text(json.dumps(data, indent=2) + "\n")
print(f"OpenCode repomix MCP configured in {config_path}")
PY
else
  echo "python3 not found — skipping OpenCode repomix MCP"
fi

# Hermes
if command -v hermes >/dev/null 2>&1; then
  python3 - <<'PY'
import sys
from pathlib import Path

config_path = Path.home() / ".hermes" / "config.yaml"
config_path.parent.mkdir(parents=True, exist_ok=True)

try:
    import yaml
except ImportError:
    print("pyyaml not found — skipping Hermes repomix MCP (pip install pyyaml to enable)")
    sys.exit(0)

data = yaml.safe_load(config_path.read_text()) if config_path.exists() else {}
if data is None:
    data = {}

data.setdefault("mcp_servers", {})["repomix"] = {
    "command": "repomix",
    "args": ["--mcp"],
}

config_path.write_text(yaml.dump(data, default_flow_style=False))
print(f"Hermes repomix MCP configured in {config_path}")
PY
else
  echo "hermes not found — skipping Hermes repomix MCP"
fi

echo "repomix MCP registered. Restart Claude Code, Codex, OpenCode, and Hermes to load it."
