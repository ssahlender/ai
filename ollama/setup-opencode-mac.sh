#!/usr/bin/env bash
# Installs OpenCode provider config for Ollama on macOS.
# Auto-discovers models from `ollama list` — no static JSON to maintain.
set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
AUTH_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json"

if ! command -v ollama >/dev/null 2>&1; then
  echo "ollama not found. Install: curl -fsSL https://ollama.com/install.sh | sh" >&2
  exit 1
fi

# --- Generate provider config from ollama list ------------------------------
generate_provider() {
  ollama list | awk 'NR > 1 && $1 != "NAME" {print $1}' | python3 -c '
import json, sys

models = {}
for line in sys.stdin:
    name = line.strip()
    if not name:
        continue
    # Derive shortname: replace : with -, keep hyphens, drop everything else risky
    short = name.replace(":", "-")
    models[short] = {"name": name}

provider = {
    "ollama": {
        "npm": "@ai-sdk/openai-compatible",
        "name": "ollama",
        "options": {
            "baseURL": "http://localhost:11434/v1",
            "apiKey": "ollama"
        },
        "models": models
    }
}

print(json.dumps(provider, indent=2))
'
}

NEW_PROVIDER=$(generate_provider)

if [ -z "$NEW_PROVIDER" ] || [ "$(echo "$NEW_PROVIDER" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d.get("ollama",{}).get("models",{})))')" -eq 0 ]; then
  echo "No Ollama models found. Run download-models-mac.sh first." >&2
  exit 1
fi

# --- Merge into opencode.json -----------------------------------------------
mkdir -p "$CONFIG_DIR"
TARGET="$CONFIG_DIR/opencode.json"

if [ -f "$TARGET" ]; then
  echo "$NEW_PROVIDER" | python3 -c "
import json, sys
new_provider = json.load(sys.stdin)
with open('$TARGET') as f:
    existing = json.load(f)
existing.setdefault('provider', {}).update(new_provider)
print(json.dumps(existing, indent=2))
" > "$TARGET.tmp" && mv "$TARGET.tmp" "$TARGET"
  echo "Merged ollama provider into $TARGET"
else
  config='{"$schema":"https://opencode.ai/config.json","provider":'"$NEW_PROVIDER"'}'
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
auth.setdefault('ollama', {'type': 'api', 'key': 'ollama'})
print(json.dumps(auth, indent=2))
" > "$AUTH_FILE.tmp" && mv "$AUTH_FILE.tmp" "$AUTH_FILE"
else
  python3 -c "
import json
auth = {'ollama': {'type': 'api', 'key': 'ollama'}}
print(json.dumps(auth, indent=2))
" > "$AUTH_FILE"
fi

echo "Updated $AUTH_FILE"
echo
echo "Available model shortnames:"
echo "$NEW_PROVIDER" | python3 -c '
import json, sys
models = json.load(sys.stdin)["ollama"]["models"]
for short, m in models.items():
    print(f"  ollama/{short}  →  {m[\"name\"]}")
'
