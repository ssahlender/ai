#!/usr/bin/env bash
# Installs the OpenCode config and registers providers in auth.json for HP ProBook (WSL2).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
AUTH_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json"

# Resolve Windows host IP from WSL2 (default gateway = Windows host)
WSL_HOST_IP=$(ip route show default | awk '{print $3; exit}')
if [ -z "$WSL_HOST_IP" ]; then
  echo "Could not detect Windows host IP from ip route." >&2
  exit 1
fi
echo "Windows host IP: $WSL_HOST_IP"

# Merge providers into opencode.json (substituting WSL_HOST_IP placeholder)
mkdir -p "$CONFIG_DIR"
TARGET="$CONFIG_DIR/opencode.json"
RESOLVED=$(sed "s/WSL_HOST_IP/$WSL_HOST_IP/g" "$SCRIPT_DIR/opencode-probook.json")

if [ -f "$TARGET" ]; then
  python3 -c "
import json, sys
with open('$TARGET') as f:
    existing = json.load(f)
new = json.loads(sys.stdin.read())
existing.setdefault('provider', {}).update(new.get('provider', {}))
print(json.dumps(existing, indent=2))
" <<< "$RESOLVED" > "$TARGET.tmp" && mv "$TARGET.tmp" "$TARGET"
  echo "Merged providers into $TARGET"
else
  echo "$RESOLVED" > "$TARGET"
  echo "Installed $TARGET"
fi

# Merge provider keys into auth.json
mkdir -p "$(dirname "$AUTH_FILE")"

PROVIDERS='["ik-llama-qwen","ik-llama-qwen36-uncensored","ik-llama-gemma"]'

if [ -f "$AUTH_FILE" ]; then
  python3 -c "
import json, sys
with open('$AUTH_FILE') as f:
    auth = json.load(f)
for key in $PROVIDERS:
    auth.setdefault(key, {'type': 'api', 'key': 'dummy'})
print(json.dumps(auth, indent=2))
" > "$AUTH_FILE.tmp" && mv "$AUTH_FILE.tmp" "$AUTH_FILE"
else
  python3 -c "
import json
providers = $PROVIDERS
auth = {k: {'type': 'api', 'key': 'dummy'} for k in providers}
print(json.dumps(auth, indent=2))
" > "$AUTH_FILE"
fi

echo "Updated $AUTH_FILE"
