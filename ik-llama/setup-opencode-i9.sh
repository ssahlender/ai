#!/usr/bin/env bash
# Installs the OpenCode config and registers providers in auth.json for i9-13900.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
AUTH_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json"

# Merge providers into opencode.json
mkdir -p "$CONFIG_DIR"
TARGET="$CONFIG_DIR/opencode.json"

if [ -f "$TARGET" ]; then
  python3 -c "
import json
with open('$TARGET') as f:
    existing = json.load(f)
with open('$SCRIPT_DIR/opencode-i9.json') as f:
    new = json.load(f)
existing.setdefault('provider', {}).update(new.get('provider', {}))
print(json.dumps(existing, indent=2))
" > "$TARGET.tmp" && mv "$TARGET.tmp" "$TARGET"
  echo "Merged providers into $TARGET"
else
  cp "$SCRIPT_DIR/opencode-i9.json" "$TARGET"
  echo "Installed $TARGET"
fi

# Merge provider keys into auth.json
mkdir -p "$(dirname "$AUTH_FILE")"

PROVIDERS='["ik-llama"]'

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
