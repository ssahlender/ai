#!/usr/bin/env bash
# Installs OpenCode/Pi provider config for mlx_lm.server.
# Parses the MODES table in start.sh. Usage: ./setup-agent.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCODE_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
OPENCODE_AUTH_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json"
PI_CONFIG_DIR="$HOME/.pi/agent"
PORT="${MLX_PORT:-8090}"
BASE_URL="http://localhost:$PORT/v1"
OPENCODE_OUTPUT_LIMIT="${OPENCODE_OUTPUT_LIMIT:-8192}"
OPENCODE_COMPACTION_RESERVED="${OPENCODE_COMPACTION_RESERVED:-10000}"
START_SCRIPT="$SCRIPT_DIR/start.sh"

_py=$(mktemp)
_apply=$(mktemp)
cleanup() { rm -f "$_py" "$_apply"; }
trap cleanup EXIT

cat > "$_py" << 'PYEOF'
import re, json, os

start_script = os.environ['START_SCRIPT']
output_limit = int(os.environ.get('OPENCODE_OUTPUT_LIMIT', '8192'))
compaction_reserved = int(os.environ.get('OPENCODE_COMPACTION_RESERVED', '10000'))

with open(start_script) as f:
    content = f.read()

# MODES entries: "shortname|display name|hf-repo|context"
modes_pattern = re.compile(r'"([\w.-]+)\|([^|]+)\|([\w./-]+)\|(\d+)"')

opencode_models = {}
pi_models = []

for shortname, _name, repo, ctx in modes_pattern.findall(content):
    context = int(ctx)
    model = {
        'name': repo,
        'limit': {'context': context, 'output': output_limit},
    }
    opencode_models[shortname] = model
    pi_models.append({
        'id': shortname,
        'name': repo,
        'contextWindow': context,
        'maxTokens': output_limit,
        'reasoning': True,
    })

compaction = {'auto': True, 'prune': True, 'reserved': compaction_reserved}

result = {
    'opencode_provider': {
        'npm': '@ai-sdk/openai-compatible',
        'name': 'mlx',
        'options': {'baseURL': os.environ['BASE_URL'], 'apiKey': 'dummy'},
        'models': opencode_models,
    },
    'pi_provider': {
        'baseUrl': os.environ['BASE_URL'],
        'api': 'openai-completions',
        'apiKey': 'dummy',
        'compat': {'supportsDeveloperRole': False, 'supportsReasoningEffort': False},
        'models': pi_models,
    },
    'compaction': compaction,
}

print(json.dumps(result, indent=2))
PYEOF

MODELS_JSON=$(START_SCRIPT="$START_SCRIPT" OPENCODE_OUTPUT_LIMIT="$OPENCODE_OUTPUT_LIMIT" OPENCODE_COMPACTION_RESERVED="$OPENCODE_COMPACTION_RESERVED" BASE_URL="$BASE_URL" python3 "$_py")

model_count=$(echo "$MODELS_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d.get("opencode_provider",{}).get("models",{})))')
if [ "$model_count" -eq 0 ]; then
  echo "No modes found in $START_SCRIPT." >&2
  exit 1
fi

cat > "$_apply" << 'PYEOF'
import json, os, sys
from pathlib import Path

opencode_config_dir = Path(os.environ['OPENCODE_CONFIG_DIR'])
opencode_config = opencode_config_dir / 'opencode.json'
opencode_auth = Path(os.environ['OPENCODE_AUTH_FILE'])
pi_config_dir = Path(os.environ['PI_CONFIG_DIR'])
pi_config = pi_config_dir / 'models.json'

generated = json.loads(sys.stdin.read())
compact = generated['compaction']

opencode_config_dir.mkdir(parents=True, exist_ok=True)
existing = json.loads(opencode_config.read_text()) if opencode_config.exists() else {}
existing.setdefault('provider', {})['mlx'] = generated['opencode_provider']
existing['compaction'] = compact
opencode_config.write_text(json.dumps(existing, indent=2) + '\n')
print(f'Merged mlx provider into {opencode_config}')

opencode_auth.parent.mkdir(parents=True, exist_ok=True)
auth = json.loads(opencode_auth.read_text()) if opencode_auth.exists() else {}
auth.setdefault('mlx', {'type': 'api', 'key': 'dummy'})
opencode_auth.write_text(json.dumps(auth, indent=2) + '\n')
print(f'Updated {opencode_auth}')

pi_config_dir.mkdir(parents=True, exist_ok=True)
pi = json.loads(pi_config.read_text()) if pi_config.exists() else {}
pi.setdefault('providers', {})['mlx'] = generated['pi_provider']
pi_config.write_text(json.dumps(pi, indent=2) + '\n')
print(f'Merged mlx provider into {pi_config}')

print()
print('Available model shortnames:')
for short, m in generated['opencode_provider']['models'].items():
    print(f'  mlx/{short}  ->  {m["name"]}')
PYEOF

echo "$MODELS_JSON" | OPENCODE_CONFIG_DIR="$OPENCODE_CONFIG_DIR" OPENCODE_AUTH_FILE="$OPENCODE_AUTH_FILE" PI_CONFIG_DIR="$PI_CONFIG_DIR" python3 "$_apply"
