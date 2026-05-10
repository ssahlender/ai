#!/usr/bin/env bash
# Installs OpenCode provider config for ik_llama.cpp on i9-13900.
# Parses start-i9.sh for model mappings — no static config file needed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
AUTH_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json"
MODELS_DIR="${MODELS_DIR:-/data/llm/models}"
START_SCRIPT="$SCRIPT_DIR/start-i9.sh"

# --- Parse start-i9.sh to extract shortname → filename.gguf -----------------
MODELS_JSON=$(python3 -c "
import re, json, os, sys

models_dir = os.environ.get('MODELS_DIR', '/data/llm/models')
start_script = os.environ['START_SCRIPT']
pattern = re.compile(r'^\s*(\S+)\)\s+start_model\s+\"[^\"]+\"\s+\"([^\"]+\.gguf)\"')

models = {}
with open(start_script) as f:
    for line in f:
        m = pattern.match(line)
        if m:
            shortname, filename = m.groups()
            if os.path.isfile(os.path.join(models_dir, filename)):
                models[shortname] = {'name': filename}

provider = {
    'ik-llama': {
        'npm': '@ai-sdk/openai-compatible',
        'name': 'ik_llama',
        'options': {
            'baseURL': 'http://localhost:9080/v1',
            'apiKey': 'dummy'
        },
        'models': models
    }
}

print(json.dumps(provider, indent=2))
" START_SCRIPT="$START_SCRIPT" MODELS_DIR="$MODELS_DIR")

if [ "$(echo "$MODELS_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d.get("ik-llama",{}).get("models",{})))')" -eq 0 ]; then
  echo "No models found in $MODELS_DIR. Run download-models-i9.sh first." >&2
  exit 1
fi

# --- Merge into opencode.json -----------------------------------------------
mkdir -p "$CONFIG_DIR"
TARGET="$CONFIG_DIR/opencode.json"

if [ -f "$TARGET" ]; then
  echo "$MODELS_JSON" | python3 -c "
import json, sys
new_provider = json.load(sys.stdin)
with open('$TARGET') as f:
    existing = json.load(f)
existing.setdefault('provider', {}).update(new_provider)
print(json.dumps(existing, indent=2))
" > "$TARGET.tmp" && mv "$TARGET.tmp" "$TARGET"
  echo "Merged ik-llama provider into $TARGET"
else
  config='{"$schema":"https://opencode.ai/config.json","provider":'"$MODELS_JSON"'}'
  echo "$config" | python3 -c "
import json, sys
cfg = json.load(sys.stdin)
print(json.dumps(cfg, indent=2))
" > "$TARGET"
  echo "Installed $TARGET"
fi

# --- Register auth ----------------------------------------------------------
mkdir -p "$(dirname "$AUTH_FILE")"

if [ -f "$AUTH_FILE" ]; then
  python3 -c "
import json
with open('$AUTH_FILE') as f:
    auth = json.load(f)
auth.setdefault('ik-llama', {'type': 'api', 'key': 'dummy'})
print(json.dumps(auth, indent=2))
" > "$AUTH_FILE.tmp" && mv "$AUTH_FILE.tmp" "$AUTH_FILE"
else
  python3 -c "
import json
auth = {'ik-llama': {'type': 'api', 'key': 'dummy'}}
print(json.dumps(auth, indent=2))
" > "$AUTH_FILE"
fi

echo "Updated $AUTH_FILE"
echo
echo "Available model shortnames:"
echo "$MODELS_JSON" | python3 -c '
import json, sys
models = json.load(sys.stdin)["ik-llama"]["models"]
for short, m in models.items():
    print(f"  ik-llama/{short}  →  {m[\"name\"]}")
'
echo
echo "Provider key: ik-llama (type the provider name in OpenCode to switch)"
