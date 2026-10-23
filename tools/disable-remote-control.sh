#!/usr/bin/env bash
set -euo pipefail

# Run as the login user; elevate only the system-policy merge, never the CLI.
agent="${1:?Usage: disable-remote-control.sh codex|claude}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "$agent" in
  codex) policy=/etc/codex/requirements.toml ;;
  claude)
    case "$(uname -s)" in
      Darwin) policy='/Library/Application Support/ClaudeCode/managed-settings.json' ;;
      Linux) policy=/etc/claude-code/managed-settings.json ;;
      *) echo 'Unsupported OS for Claude managed policy' >&2; exit 1 ;;
    esac
    ;;
  *) echo "Unknown agent: $agent" >&2; exit 1 ;;
esac

python_bin="$(command -v python3)"
if [ "$agent" = codex ] && ! "$python_bin" -c 'import tomllib' 2>/dev/null; then
  echo 'Codex policy management requires Python 3.11+ (tomllib).' >&2
  exit 1
fi
if [ "$agent" = codex ]; then
  codex app-server daemon disable-remote-control
fi
if "$python_bin" "$script_dir/_disable-remote-control.py" "$agent" "$policy" --check; then
  : # Already enforced: routine updates need no elevated write.
elif [ "$(id -u)" -eq 0 ]; then
  "$python_bin" "$script_dir/_disable-remote-control.py" "$agent" "$policy"
else
  # No unattended password prompts during update-all.sh. Fail visibly if not authorized.
  if ! sudo -n "$python_bin" "$script_dir/_disable-remote-control.py" "$agent" "$policy"; then
    echo "Could not enforce $agent system policy. Run sudo -v in your terminal and retry." >&2
    exit 1
  fi
fi
echo "$agent: remote control disabled ($policy)"
