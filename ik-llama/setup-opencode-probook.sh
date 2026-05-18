#!/usr/bin/env bash
# Installs OpenCode provider config for ik_llama.cpp on HP ProBook (WSL2).
# Parses start-probook.sh for model mappings — no static config file needed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
AUTH_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json"
MODELS_DIR="${MODELS_DIR:-/mnt/c/data/llm/models}"
START_SCRIPT="$SCRIPT_DIR/start-probook.sh"
OPENCODE_OUTPUT_LIMIT="${OPENCODE_OUTPUT_LIMIT:-8192}"
OPENCODE_COMPACTION_RESERVED="${OPENCODE_COMPACTION_RESERVED:-10000}"

# Detect Windows host IP from WSL2 default gateway
WSL_HOST_IP=$(ip route show default | awk '{print $3; exit}')
if [ -z "$WSL_HOST_IP" ]; then
  echo "Could not detect Windows host IP from ip route." >&2
  exit 1
fi
echo "Windows host IP: $WSL_HOST_IP"

# --- Parse start-probook.sh to extract shortname → filename.gguf ------------
MODELS_JSON=$(START_SCRIPT="$START_SCRIPT" MODELS_DIR="$MODELS_DIR" WSL_HOST_IP="$WSL_HOST_IP" OPENCODE_OUTPUT_LIMIT="$OPENCODE_OUTPUT_LIMIT" python3 -c "
import re, json, os, sys

models_dir = os.environ['MODELS_DIR']
start_script = os.environ['START_SCRIPT']
wsl_ip = os.environ['WSL_HOST_IP']
output_limit = int(os.environ.get('OPENCODE_OUTPUT_LIMIT', '8192'))
ctx_override = os.environ.get('IK_LLAMA_CTX_SIZE')
pattern = re.compile(r'^\s*(\S+)\)\s+start_model\s+\"[^\"]+\"\s+\"([^\"]+\.gguf)\"\s+(\d+)')

models = {}
with open(start_script) as f:
    for line in f:
        m = pattern.match(line)
        if m:
            shortname, filename, ctx = m.groups()
            if os.path.isfile(os.path.join(models_dir, filename)):
                models[shortname] = {
                    'name': filename,
                    'limit': {
                        'context': int(ctx_override or ctx),
                        'output': output_limit
                    }
                }

provider = {
    'ik-llama': {
        'npm': '@ai-sdk/openai-compatible',
        'name': 'ik_llama',
        'options': {
            'baseURL': f'http://{wsl_ip}:8080/v1',
            'apiKey': 'dummy'
        },
        'models': models
    }
}

print(json.dumps(provider, indent=2))
")

if [ "$(echo "$MODELS_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d.get("ik-llama",{}).get("models",{})))')" -eq 0 ]; then
  echo "No models found in $MODELS_DIR. Run download-models-probook.sh first." >&2
  exit 1
fi

# --- Merge into opencode.json -----------------------------------------------
mkdir -p "$CONFIG_DIR"
TARGET="$CONFIG_DIR/opencode.json"
COMPACTION_JSON=$(OPENCODE_COMPACTION_RESERVED="$OPENCODE_COMPACTION_RESERVED" python3 -c '
import json, os
print(json.dumps({
    "auto": True,
    "prune": True,
    "reserved": int(os.environ.get("OPENCODE_COMPACTION_RESERVED", "10000")),
}))
')

if [ -f "$TARGET" ]; then
  echo "$MODELS_JSON" | python3 -c "
import json, sys
new_provider = json.load(sys.stdin)
with open('$TARGET') as f:
    existing = json.load(f)
existing.setdefault('provider', {}).update(new_provider)
existing['compaction'] = json.loads('''$COMPACTION_JSON''')
print(json.dumps(existing, indent=2))
" > "$TARGET.tmp" && mv "$TARGET.tmp" "$TARGET"
  echo "Merged ik-llama provider into $TARGET"
else
  # shellcheck disable=SC2016
  config='{"$schema":"https://opencode.ai/config.json","provider":'"$MODELS_JSON"',"compaction":'"$COMPACTION_JSON"'}'
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
    print("  ik-llama/{}  →  {}".format(short, m["name"]))
'
echo
echo "Provider key: ik-llama (type the provider name in OpenCode to switch)"
echo "OpenCode limits: context from start-probook.sh${IK_LLAMA_CTX_SIZE:+ overridden by IK_LLAMA_CTX_SIZE=$IK_LLAMA_CTX_SIZE}, output=$OPENCODE_OUTPUT_LIMIT, compaction reserved=$OPENCODE_COMPACTION_RESERVED"
