#!/usr/bin/env bash
# Toggle OpenCode helpers that can add latency around local model tool calls.
set -euo pipefail

ACTION="${1:-status}"
CONFIG_DIR="${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}"
CONFIG_PATH="${OPENCODE_CONFIG:-$CONFIG_DIR/opencode.json}"
PLUGIN_DIR="$CONFIG_DIR/plugins"
DISABLED_PLUGIN_DIR="$CONFIG_DIR/plugins.disabled"
PLUGIN_BACKUP="$CONFIG_DIR/opencode.plugins.local-speed.json"

usage() {
  cat <<EOF
Usage: $0 [status|fast|restore]

  status   Show OpenCode plugin and MCP state.
  fast     Disable context-mode MCP and all configured/auto-loaded plugins.
  restore  Re-enable context-mode MCP and restore disabled plugins.

Set OPENCODE_CONFIG or OPENCODE_CONFIG_DIR to target a non-default config.
EOF
}

if [ "$ACTION" = "-h" ] || [ "$ACTION" = "--help" ]; then
  usage
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 not found" >&2
  exit 1
fi

case "$ACTION" in
  status|fast|restore) ;;
  *)
    usage >&2
    exit 1
    ;;
esac

ACTION="$ACTION" CONFIG_PATH="$CONFIG_PATH" PLUGIN_BACKUP="$PLUGIN_BACKUP" python3 - <<'PY'
import json
import os
from pathlib import Path

action = os.environ["ACTION"]
config_path = Path(os.environ["CONFIG_PATH"]).expanduser()
plugin_backup = Path(os.environ["PLUGIN_BACKUP"]).expanduser()

if not config_path.exists():
    raise SystemExit(f"{config_path} does not exist")

try:
    data = json.loads(config_path.read_text())
except json.JSONDecodeError as exc:
    raise SystemExit(f"{config_path} is not valid JSON: {exc}")

plugins = data.get("plugin", [])
mcp = data.get("mcp", {})

if action == "status":
    print(f"Config: {config_path}")
    print("Plugins:")
    if plugins:
        for plugin in plugins:
            print(f"  {plugin}")
    else:
        print("  none")
    print(f"Plugin config backup: {'yes' if plugin_backup.exists() else 'no'}")
    print("MCP:")
    if mcp:
        for name, cfg in mcp.items():
            enabled = cfg.get("enabled", True) if isinstance(cfg, dict) else True
            print(f"  {name}: enabled={enabled}")
    else:
        print("  none")
    raise SystemExit(0)

if action == "fast":
    if isinstance(plugins, list):
        plugin_backup.write_text(json.dumps(plugins, indent=2) + "\n")
        data["plugin"] = []
    if isinstance(mcp.get("context-mode"), dict):
        mcp["context-mode"]["enabled"] = False
    data["mcp"] = mcp
    config_path.write_text(json.dumps(data, indent=2) + "\n")
    print(f"OpenCode local-speed mode written to {config_path}")
    print("Disabled context-mode MCP and cleared configured plugin entries.")
    raise SystemExit(0)

if action == "restore":
    data.setdefault("mcp", {})
    data["mcp"]["context-mode"] = {
        "type": "local",
        "command": ["context-mode"],
        "enabled": True,
    }
    if plugin_backup.exists():
        try:
            data["plugin"] = json.loads(plugin_backup.read_text())
        except json.JSONDecodeError as exc:
            raise SystemExit(f"{plugin_backup} is not valid JSON: {exc}")
    config_path.write_text(json.dumps(data, indent=2) + "\n")
    print(f"OpenCode context-mode MCP restored in {config_path}")
    if plugin_backup.exists():
        print(f"OpenCode plugin entries restored from {plugin_backup}")
PY

if [ "$ACTION" = "fast" ] && [ -d "$PLUGIN_DIR" ]; then
  mkdir -p "$DISABLED_PLUGIN_DIR"
  shopt -s nullglob dotglob
  for plugin in "$PLUGIN_DIR"/*; do
    [ -e "$plugin" ] || continue
    target="$DISABLED_PLUGIN_DIR/$(basename "$plugin")"
    target="${target%.disabled}"
    mv "$plugin" "$target"
    echo "Disabled plugin file: $plugin"
  done
  shopt -u nullglob dotglob
fi

if [ "$ACTION" = "restore" ] && [ -d "$DISABLED_PLUGIN_DIR" ]; then
  mkdir -p "$PLUGIN_DIR"
  shopt -s nullglob dotglob
  for plugin in "$DISABLED_PLUGIN_DIR"/*; do
    [ -e "$plugin" ] || continue
    mv "$plugin" "$PLUGIN_DIR/"
    echo "Restored plugin file: $PLUGIN_DIR/$(basename "$plugin")"
  done
  shopt -u nullglob dotglob
fi
