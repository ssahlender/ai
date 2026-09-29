#!/usr/bin/env bash
# Installs OpenCode/Pi provider config for Ollama's OpenAI-compatible API.
# Usage: ./setup-agent.sh
set -euo pipefail

OPENCODE_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
OPENCODE_AUTH_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json"
PI_CONFIG_DIR="$HOME/.pi/agent"
PORT="${OLLAMA_HOST_PORT:-11434}"
BASE_URL="http://localhost:$PORT/v1"
OPENCODE_OUTPUT_LIMIT="${OPENCODE_OUTPUT_LIMIT:-8192}"
OPENCODE_COMPACTION_RESERVED="${OPENCODE_COMPACTION_RESERVED:-10000}"

# shortname|display name|ollama model tag|context window
MODES=(
  "qwen36-35b-a3b|Qwen3.6-35B-A3B (Ollama, UD-Q2_K_XL 13 GB)|qwen36-35b-a3b|32768"
)

_py=$(mktemp)
_apply=$(mktemp)
cleanup() { rm -f "$_py" "$_apply"; }
trap cleanup EXIT

cat > "$_py" << 'PYEOF'
import json, os

output_limit = int(os.environ.get('OPENCODE_OUTPUT_LIMIT', '8192'))
compaction_reserved = int(os.environ.get('OPENCODE_COMPACTION_RESERVED', '10000'))
modes = json.loads(os.environ['MODES_JSON'])

opencode_models = {}
pi_models = []

for shortname, _name, tag, ctx in modes:
    context = int(ctx)
    opencode_models[shortname] = {
        'name': tag,
        'limit': {'context': context, 'output': output_limit},
    }
    pi_models.append({
        'id': shortname,
        'name': tag,
        'contextWindow': context,
        'maxTokens': output_limit,
        'reasoning': True,
    })

compaction = {'auto': True, 'prune': True, 'reserved': compaction_reserved}

result = {
    'opencode_provider': {
        'npm': '@ai-sdk/openai-compatible',
        'name': 'ollama',
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

MODES_JSON=$(python3 -c "
import json, sys
modes = []
for m in sys.argv[1:]:
    modes.append(m.split('|'))
print(json.dumps(modes))
" "${MODES[@]}")

RESULT_JSON=$(MODES_JSON="$MODES_JSON" OPENCODE_OUTPUT_LIMIT="$OPENCODE_OUTPUT_LIMIT" OPENCODE_COMPACTION_RESERVED="$OPENCODE_COMPACTION_RESERVED" BASE_URL="$BASE_URL" python3 "$_py")

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
existing.setdefault('provider', {})['ollama'] = generated['opencode_provider']
existing['compaction'] = compact
opencode_config.write_text(json.dumps(existing, indent=2) + '\n')
print(f'Merged ollama provider into {opencode_config}')

opencode_auth.parent.mkdir(parents=True, exist_ok=True)
auth = json.loads(opencode_auth.read_text()) if opencode_auth.exists() else {}
auth.setdefault('ollama', {'type': 'api', 'key': 'dummy'})
opencode_auth.write_text(json.dumps(auth, indent=2) + '\n')
print(f'Updated {opencode_auth}')

pi_config_dir.mkdir(parents=True, exist_ok=True)
pi = json.loads(pi_config.read_text()) if pi_config.exists() else {}
pi.setdefault('providers', {})['ollama'] = generated['pi_provider']
pi_config.write_text(json.dumps(pi, indent=2) + '\n')
print(f'Merged ollama provider into {pi_config}')

print()
print('Available model shortnames:')
for short, m in generated['opencode_provider']['models'].items():
    print(f'  ollama/{short}  ->  {m["name"]}')
print()
print('NOTE: thinking is on by default and is set per-request - Ollama has no')
print('server-wide switch. On /v1/chat/completions, the endpoint OpenCode and Pi')
print('below use, the working knob is  "reasoning_effort": "none"  which measured')
print('0 reasoning bytes against 132 tokens when left unset. "think": false is')
print('IGNORED there - it made the model think MORE, so do not reach for it.')
print('Trap: with a small max_tokens the model can spend the whole budget inside')
print('reasoning and return empty content. See README.md for the measured table.')
PYEOF

echo "$RESULT_JSON" | OPENCODE_CONFIG_DIR="$OPENCODE_CONFIG_DIR" OPENCODE_AUTH_FILE="$OPENCODE_AUTH_FILE" PI_CONFIG_DIR="$PI_CONFIG_DIR" python3 "$_apply"
