#!/usr/bin/env bash
# Installs agent provider config for ik_llama.cpp / llama.cpp.
# Parses the start script for model mappings.
# Usage: ./setup-agents.sh [i9|probook|macbook-air]
set -euo pipefail

MACHINE="${1:-}"

[ -n "$MACHINE" ] || { echo "Usage: $0 [i9|probook|macbook-air]" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCODE_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
OPENCODE_AUTH_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json"
PI_CONFIG_DIR="$HOME/.pi/agent"
OPENCODE_OUTPUT_LIMIT="${OPENCODE_OUTPUT_LIMIT:-8192}"
OPENCODE_COMPACTION_RESERVED="${OPENCODE_COMPACTION_RESERVED:-10000}"
START_SCRIPT="$SCRIPT_DIR/start.sh"

case "$MACHINE" in
  i9)
    MODELS_DIR="${MODELS_DIR:-/data/llm/models}"
    BASE_URL="http://localhost:9080/v1"
    ;;
  probook)
    MODELS_DIR="${MODELS_DIR:-/mnt/c/data/llm/models}"
    WSL_HOST_IP=$(ip route show default | awk '{print $3; exit}')
    [ -n "$WSL_HOST_IP" ] || { echo "Could not detect Windows host IP." >&2; exit 1; }
    echo "Windows host IP: $WSL_HOST_IP"
    BASE_URL="http://$WSL_HOST_IP:9080/v1"
    ;;
  macbook-air)
    MODELS_DIR="${MODELS_DIR:-$HOME/.local/share/llama.cpp/models}"
    BASE_URL="http://localhost:9080/v1"
    ;;
  *) echo "Usage: $0 [i9|probook|macbook-air]" >&2; exit 1 ;;
esac

# ── write a temporary Python script that auto-collects parameters ──
_py=$(mktemp)
cleanup() { rm -f "$_py"; }
trap cleanup EXIT

cat > "$_py" << 'PYEOF'
import re, json, os, sys

models_dir = os.environ['MODELS_DIR']
start_script = os.environ['START_SCRIPT']
machine = os.environ['MACHINE']
output_limit = int(os.environ.get('OPENCODE_OUTPUT_LIMIT', '8192'))
ctx_override = os.environ.get('IK_LLAMA_CTX_SIZE')
compaction_reserved = int(os.environ.get('OPENCODE_COMPACTION_RESERVED', '10000'))

with open(start_script) as f:
    content = f.read()

# Extract MODES entries within the machine's case block
in_block = False
modes_pattern = re.compile(r'"([^"]+)\|([^"]+)\|([^"]+\.gguf)\|(\d+)\|(\d+)')

opencode_models = {}
pi_models = []

for line in content.split('\n'):
    if re.match(r'^\s*' + re.escape(machine) + r'\)\s*$', line):
        in_block = True
        continue
    if in_block and re.match(r'^\s*;;\s*$', line):
        in_block = False
        continue
    if not in_block:
        continue

    m = modes_pattern.search(line)
    if m:
        shortname, _name, filename, ctx, cram = m.groups()
        if os.path.isfile(os.path.join(models_dir, filename)):
            context = int(ctx_override or ctx)
            is_vision = 'mmproj-' in line
            model = {
                'name': filename,
                'limit': {'context': context, 'output': output_limit}
            }
            if is_vision:
                model['modalities'] = {
                    'input': ['text', 'image'],
                    'output': ['text']
                }
            opencode_models[shortname] = model
            pi_model = {
                'id': shortname,
                'name': filename,
                'contextWindow': context,
                'maxTokens': output_limit,
                'reasoning': False,
            }
            if is_vision:
                pi_model['attachment'] = True
            pi_models.append(pi_model)

compaction = {
    'auto': True,
    'prune': True,
    'reserved': compaction_reserved,
}

result = {
    'opencode_provider': {
        'npm': '@ai-sdk/openai-compatible',
        'name': 'ik-llama',
        'options': {'baseURL': os.environ['BASE_URL'], 'apiKey': 'dummy'},
        'models': opencode_models
    },
    'pi_provider': {
        'baseUrl': os.environ['BASE_URL'],
        'api': 'openai-completions',
        'apiKey': 'dummy',
        'compat': {'supportsDeveloperRole': False, 'supportsReasoningEffort': False},
        'models': pi_models
    },
    'compaction': compaction,
}

print(json.dumps(result, indent=2))
PYEOF

# ── execute the Python script ──────────────────────────────────────
MODELS_JSON=$(START_SCRIPT="$START_SCRIPT" MODELS_DIR="$MODELS_DIR" MACHINE="$MACHINE" OPENCODE_OUTPUT_LIMIT="$OPENCODE_OUTPUT_LIMIT" OPENCODE_COMPACTION_RESERVED="$OPENCODE_COMPACTION_RESERVED" BASE_URL="$BASE_URL" python3 "$_py")

model_count=$(echo "$MODELS_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d.get("opencode_provider",{}).get("models",{})))')
if [ "$model_count" -eq 0 ]; then
  echo "No models found in $MODELS_DIR. Run download-models.sh $MACHINE first." >&2
  exit 1
fi

# ── fuse generated data into an output Python snippet ──────────────
_apply=$(mktemp)
cleanup() { rm -f "$_py" "$_apply"; }
trap cleanup EXIT

cat > "$_apply" << PYEOF
import json, os, sys
from pathlib import Path

opencode_config_dir = Path(os.environ['OPENCODE_CONFIG_DIR'])
opencode_config = opencode_config_dir / 'opencode.json'
opencode_auth = Path(os.environ['OPENCODE_AUTH_FILE'])
pi_config_dir = Path(os.environ['PI_CONFIG_DIR'])
pi_config = pi_config_dir / 'models.json'

# generated JSON is read from stdin
MODELS_JSON = sys.stdin.read()

generated = json.loads(MODELS_JSON)
compact = generated['compaction']

# ── OpenCode ───────────────────────────────────────────────────────
opencode_config_dir.mkdir(parents=True, exist_ok=True)

if opencode_config.exists():
    existing = json.loads(opencode_config.read_text())
else:
    existing = {}
existing.setdefault('provider', {})['ik-llama'] = generated['opencode_provider']
existing['compaction'] = compact
opencode_config.write_text(json.dumps(existing, indent=2) + '\n')
print(f'Merged ik-llama provider into {opencode_config}')

# ── OpenCode auth ──────────────────────────────────────────────────
opencode_auth.parent.mkdir(parents=True, exist_ok=True)
auth = json.loads(opencode_auth.read_text()) if opencode_auth.exists() else {}
auth.setdefault('ik-llama', {'type': 'api', 'key': 'dummy'})
opencode_auth.write_text(json.dumps(auth, indent=2) + '\n')
print(f'Updated {opencode_auth}')

# ── Pi ─────────────────────────────────────────────────────────────
pi_config_dir.mkdir(parents=True, exist_ok=True)
pi = json.loads(pi_config.read_text()) if pi_config.exists() else {}
pi.setdefault('providers', {})['ik-llama'] = generated['pi_provider']
pi_config.write_text(json.dumps(pi, indent=2) + '\n')
print(f'Merged ik-llama provider into {pi_config}')

# ── list models ────────────────────────────────────────────────────
print()
print('Available model shortnames:')
for short, m in generated['opencode_provider']['models'].items():
    print(f'  ik-llama/{short}  ->  {m["name"]}')
print()
print(f'Provider key: ik-llama')
print(f"Limits: output={os.environ['OPENCODE_OUTPUT_LIMIT']}, compaction reserved={os.environ['OPENCODE_COMPACTION_RESERVED']}")
PYEOF

echo "$MODELS_JSON" | OPENCODE_CONFIG_DIR="$OPENCODE_CONFIG_DIR" OPENCODE_AUTH_FILE="$OPENCODE_AUTH_FILE" PI_CONFIG_DIR="$PI_CONFIG_DIR" OPENCODE_OUTPUT_LIMIT="$OPENCODE_OUTPUT_LIMIT" OPENCODE_COMPACTION_RESERVED="$OPENCODE_COMPACTION_RESERVED" python3 "$_apply"
