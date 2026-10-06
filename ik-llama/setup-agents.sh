#!/usr/bin/env bash
# Installs agent provider config for ik_llama.cpp / llama.cpp.
# Parses the start script for model mappings.
# Usage: ./setup-agents.sh <i9|macbook-air> [--dry-run]
# Model ids are GGUF stems (file name without .gguf). Besides writing the ik-llama provider,
# it removes stale references to models that are no longer in start.sh / on disk.
set -euo pipefail

MACHINE="${1:-}"
DRY_RUN=0
case "${2:-}" in
  "") ;;
  --dry-run) DRY_RUN=1 ;;
  *) echo "Usage: $0 <i9|macbook-air> [--dry-run]" >&2; exit 1 ;;
esac

[ -n "$MACHINE" ] || { echo "Usage: $0 <i9|macbook-air> [--dry-run]" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCODE_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
OPENCODE_AUTH_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json"
PI_CONFIG_DIR="$HOME/.pi/agent"
OPENCODE_OUTPUT_LIMIT="${OPENCODE_OUTPUT_LIMIT:-8192}"
OPENCODE_COMPACTION_RESERVED="${OPENCODE_COMPACTION_RESERVED:-10000}"
START_SCRIPT="$SCRIPT_DIR/start.sh"

PORT="${IK_LLAMA_PORT:-9080}"

case "$MACHINE" in
  i9)
    MODELS_DIR="${MODELS_DIR:-/data/llm/models}"
    BASE_URL="http://localhost:${PORT}/v1"
    ;;
  probook)
    echo "WSL is retired on ProBook. Agent providers on Windows are configured natively via PowerShell:" >&2
    echo "  powershell -File llm/setup-agent-providers.ps1  (or ..\\llm\\setup-agent-providers.ps1 from ik-llama)" >&2
    exit 1
    ;;
  macbook-air)
    MODELS_DIR="${MODELS_DIR:-$HOME/.local/share/llama.cpp/models}"
    BASE_URL="http://localhost:${PORT}/v1"
    ;;
  *) echo "Usage: $0 <i9|macbook-air> [--dry-run]" >&2; exit 1 ;;
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
in_config = False
in_block = False
modes_pattern = re.compile(r'"([^"|]+)\|([^"|]+\.gguf)\|(\d+)\|(\d+)')

opencode_models = {}
pi_models = []

for line in content.split('\n'):
    if '# ── machine config' in line:
        in_config = True
    if not in_config:
        continue
    if re.match(r'^\s*' + re.escape(machine) + r'\)\s*$', line):
        in_block = True
        continue
    if in_block and re.search(r';;\s*$', line):
        break
    if not in_block:
        continue

    m = modes_pattern.search(line)
    if m:
        _desc, filename, ctx, cram = m.groups()
        model_id = filename[:-len('.gguf')]
        if os.path.isfile(os.path.join(models_dir, filename)):
            context = int(ctx_override or ctx)
            is_vision = 'mmproj-' in line
            model = {
                'name': model_id,
                'limit': {'context': context, 'output': output_limit}
            }
            if is_vision:
                model['modalities'] = {
                    'input': ['text', 'image'],
                    'output': ['text']
                }
            opencode_models[model_id] = model
            pi_model = {
                'id': model_id,
                'name': model_id,
                'contextWindow': context,
                'maxTokens': output_limit,
                'reasoning': False,
            }
            if is_vision:
                pi_model['attachment'] = True
                pi_model['input'] = ['text', 'image']
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

cat > "$_apply" << 'PYEOF'
import json, os, sys
from pathlib import Path

opencode_config = Path(os.environ['OPENCODE_CONFIG_DIR']) / 'opencode.json'
opencode_auth = Path(os.environ['OPENCODE_AUTH_FILE'])
pi_config = Path(os.environ['PI_CONFIG_DIR']) / 'models.json'
pi_settings = Path(os.environ['PI_CONFIG_DIR']) / 'settings.json'
dry = os.environ.get('DRY_RUN') == '1'
PROVIDER = 'ik-llama'


class ConfigError(Exception):
    pass


def load(path, what):
    """Existing JSON object, or {} when the file is absent. Anything else aborts the whole run."""
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text())
    except ValueError as e:
        raise ConfigError(f'{path}: not valid JSON ({e}); comments (JSONC) are not supported')
    if not isinstance(data, dict):
        raise ConfigError(f'{path}: expected a JSON object at the top level')
    return data


def need_dict(parent, key, path):
    """parent[key] as a dict (created when missing or null); any other type aborts."""
    val = parent.get(key)
    if val is None:
        val = parent[key] = {}
    if not isinstance(val, dict):
        raise ConfigError(f'{path}: "{key}" is {type(val).__name__}, expected an object')
    return val


generated = json.loads(sys.stdin.read())
valid = set(generated['opencode_provider']['models'])
removed = []


def stale_ref(ref):
    """True for an 'ik-llama/<id>' reference whose model is no longer served."""
    return (isinstance(ref, str) and ref.startswith(PROVIDER + '/')
            and ref.split('/', 1)[1] not in valid)


try:
    # ── phase 1: load and validate everything before changing anything ──
    oc = load(opencode_config, 'OpenCode config')
    auth = load(opencode_auth, 'OpenCode auth')
    pi = load(pi_config, 'Pi models')
    st = load(pi_settings, 'Pi settings')

    oc_providers = need_dict(oc, 'provider', opencode_config)
    old_oc = oc_providers.get(PROVIDER)
    if old_oc is not None and not isinstance(old_oc, dict):
        raise ConfigError(f'{opencode_config}: provider.{PROVIDER} is not an object')
    agents = need_dict(oc, 'agent', opencode_config) if 'agent' in oc else {}
    pi_providers = need_dict(pi, 'providers', pi_config)
    old_pi = pi_providers.get(PROVIDER)
    if old_pi is not None:
        if not isinstance(old_pi, dict) or not isinstance(old_pi.get('models', []), list):
            raise ConfigError(f'{pi_config}: providers.{PROVIDER}.models is not a list')

    # ── phase 2: compute the new state in memory ──
    for gone in sorted(set((old_oc or {}).get('models') or {}) - valid):
        removed.append(f'OpenCode provider model: {gone}')
    oc_providers[PROVIDER] = generated['opencode_provider']
    oc['compaction'] = generated['compaction']
    for key in ('model', 'small_model'):
        if stale_ref(oc.get(key)):
            removed.append(f'OpenCode {key}: {oc[key]}')
            del oc[key]
    for name, agent in agents.items():
        if not isinstance(agent, dict):
            continue
        for key in ('model', 'small_model'):
            if stale_ref(agent.get(key)):
                removed.append(f'OpenCode agent "{name}" {key}: {agent[key]}')
                del agent[key]

    auth_changed = PROVIDER not in auth
    if auth_changed:
        auth[PROVIDER] = {'type': 'api', 'key': 'dummy'}

    old_pi_ids = {m.get('id') for m in (old_pi or {}).get('models', []) if isinstance(m, dict)}
    for gone in sorted(x for x in old_pi_ids - valid if x):
        removed.append(f'Pi provider model: {gone}')
    pi_providers[PROVIDER] = generated['pi_provider']

    st_changed = False
    if st.get('defaultProvider') == PROVIDER and 'defaultModel' in st and st['defaultModel'] not in valid:
        removed.append(f'Pi defaultModel: {st["defaultModel"]} (choose a new one with /model)')
        del st['defaultModel']
        st_changed = True
except ConfigError as e:
    print(f'Refusing to change anything: {e}', file=sys.stderr)
    sys.exit(1)

# ── phase 3: write ──
def write(path, data):
    if dry:
        print(f'[dry-run] would write {path}')
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data, indent=2) + '\n')
        print(f'Wrote {path}')


write(opencode_config, oc)
if auth_changed:
    write(opencode_auth, auth)
write(pi_config, pi)
if st_changed:
    write(pi_settings, st)

# ── report ──
print()
if removed:
    print('Stale settings ' + ('that would be removed:' if dry else 'removed:'))
    for r in removed:
        print(f'  - {r}')
else:
    print('No stale settings found.')
print()
print('Available models (use as ik-llama/<name>):')
for mid in generated['opencode_provider']['models']:
    print(f'  ik-llama/{mid}')
print()
print(f'Limits: output={os.environ["OPENCODE_OUTPUT_LIMIT"]}, compaction reserved={os.environ["OPENCODE_COMPACTION_RESERVED"]}')
PYEOF

echo "$MODELS_JSON" | DRY_RUN="$DRY_RUN" OPENCODE_CONFIG_DIR="$OPENCODE_CONFIG_DIR" OPENCODE_AUTH_FILE="$OPENCODE_AUTH_FILE" PI_CONFIG_DIR="$PI_CONFIG_DIR" OPENCODE_OUTPUT_LIMIT="$OPENCODE_OUTPUT_LIMIT" OPENCODE_COMPACTION_RESERVED="$OPENCODE_COMPACTION_RESERVED" python3 "$_apply"
