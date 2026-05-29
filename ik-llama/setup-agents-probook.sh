#!/usr/bin/env bash
# Installs agent provider config for ik_llama.cpp on HP ProBook (WSL2).
# Parses start-probook.sh for model mappings — no static config file needed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCODE_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
OPENCODE_AUTH_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json"
PI_CONFIG_DIR="$HOME/.pi/agent"
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
BASE_URL="http://$WSL_HOST_IP:8080/v1"

# --- Parse start-probook.sh to extract shortname → filename.gguf ------------
MODELS_JSON=$(START_SCRIPT="$START_SCRIPT" MODELS_DIR="$MODELS_DIR" BASE_URL="$BASE_URL" OPENCODE_OUTPUT_LIMIT="$OPENCODE_OUTPUT_LIMIT" python3 -c "
import re, json, os, sys

models_dir = os.environ['MODELS_DIR']
start_script = os.environ['START_SCRIPT']
base_url = os.environ['BASE_URL']
output_limit = int(os.environ.get('OPENCODE_OUTPUT_LIMIT', '8192'))
ctx_override = os.environ.get('IK_LLAMA_CTX_SIZE')
pattern = re.compile(r'^\s*(\S+)\)\s+start_model\s+\"[^\"]+\"\s+\"([^\"]+\.gguf)\"\s+(\d+)')

opencode_models = {}
pi_models = []
with open(start_script) as f:
    for line in f:
        m = pattern.match(line)
        if m:
            shortname, filename, ctx = m.groups()
            if os.path.isfile(os.path.join(models_dir, filename)):
                context = int(ctx_override or ctx)
                opencode_models[shortname] = {
                    'name': filename,
                    'limit': {
                        'context': context,
                        'output': output_limit
                    }
                }
                pi_models.append({
                    'id': shortname,
                    'name': filename,
                    'contextWindow': context,
                    'maxTokens': output_limit,
                    'reasoning': False,
                })

config = {
    'opencode_provider': {
        'npm': '@ai-sdk/openai-compatible',
        'name': 'ik_llama',
        'options': {
            'baseURL': base_url,
            'apiKey': 'dummy'
        },
        'models': opencode_models
    },
    'pi_provider': {
        'baseUrl': base_url,
        'api': 'openai-completions',
        'apiKey': 'dummy',
        'compat': {
            'supportsDeveloperRole': False,
            'supportsReasoningEffort': False
        },
        'models': pi_models
    }
}

print(json.dumps(config, indent=2))
")

if [ "$(echo "$MODELS_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d.get("opencode_provider",{}).get("models",{})))')" -eq 0 ]; then
  echo "No models found in $MODELS_DIR. Run download-models-probook.sh first." >&2
  exit 1
fi

# --- Merge into opencode.json -----------------------------------------------
if command -v opencode >/dev/null 2>&1; then
  mkdir -p "$OPENCODE_CONFIG_DIR"
  TARGET="$OPENCODE_CONFIG_DIR/opencode.json"
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
generated = json.load(sys.stdin)
with open('$TARGET') as f:
    existing = json.load(f)
existing.setdefault('provider', {})['ik-llama'] = generated['opencode_provider']
existing['compaction'] = json.loads('''$COMPACTION_JSON''')
print(json.dumps(existing, indent=2))
" > "$TARGET.tmp" && mv "$TARGET.tmp" "$TARGET"
    echo "Merged ik-llama provider into $TARGET"
  else
    # shellcheck disable=SC2016
    config='{"$schema":"https://opencode.ai/config.json","provider":{"ik-llama":'"$(echo "$MODELS_JSON" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["opencode_provider"]))')"'},"compaction":'"$COMPACTION_JSON"'}'
    echo "$config" | python3 -c "
import json, sys
cfg = json.load(sys.stdin)
print(json.dumps(cfg, indent=2))
" > "$TARGET"
    echo "Installed $TARGET"
  fi

  # --- Register OpenCode auth ----------------------------------------------
  mkdir -p "$(dirname "$OPENCODE_AUTH_FILE")"

  if [ -f "$OPENCODE_AUTH_FILE" ]; then
    python3 -c "
import json
with open('$OPENCODE_AUTH_FILE') as f:
    auth = json.load(f)
auth.setdefault('ik-llama', {'type': 'api', 'key': 'dummy'})
print(json.dumps(auth, indent=2))
" > "$OPENCODE_AUTH_FILE.tmp" && mv "$OPENCODE_AUTH_FILE.tmp" "$OPENCODE_AUTH_FILE"
  else
    python3 -c "
import json
auth = {'ik-llama': {'type': 'api', 'key': 'dummy'}}
print(json.dumps(auth, indent=2))
" > "$OPENCODE_AUTH_FILE"
  fi

  echo "Updated $OPENCODE_AUTH_FILE"
else
  echo "opencode not found — skipping OpenCode config"
fi

# --- Merge into Pi models.json ----------------------------------------------
if command -v pi >/dev/null 2>&1; then
  mkdir -p "$PI_CONFIG_DIR"
  TARGET="$PI_CONFIG_DIR/models.json"
  echo "$MODELS_JSON" | TARGET="$TARGET" python3 -c '
import json, os, sys
from pathlib import Path

generated = json.load(sys.stdin)
target = Path(os.environ["TARGET"])
if target.exists():
    try:
        existing = json.loads(target.read_text())
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{target} is not valid JSON: {exc}")
else:
    existing = {}

existing.setdefault("providers", {})["ik-llama"] = generated["pi_provider"]
target.write_text(json.dumps(existing, indent=2) + "\n")
'
  echo "Merged ik-llama provider into $TARGET"
else
  echo "pi not found — skipping Pi config"
fi

echo
echo "Available model shortnames:"
echo "$MODELS_JSON" | python3 -c '
import json, sys
models = json.load(sys.stdin)["opencode_provider"]["models"]
for short, m in models.items():
    print("  ik-llama/{}  →  {}".format(short, m["name"]))
'
echo
echo "Provider key: ik-llama"
echo "Limits: context from start-probook.sh${IK_LLAMA_CTX_SIZE:+ overridden by IK_LLAMA_CTX_SIZE=$IK_LLAMA_CTX_SIZE}, output=$OPENCODE_OUTPUT_LIMIT, OpenCode compaction reserved=$OPENCODE_COMPACTION_RESERVED"
