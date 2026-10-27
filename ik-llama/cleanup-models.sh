#!/usr/bin/env bash
# Removes model files not in the active start.sh lineup. Dry-run by default.
# Usage:
#   ./cleanup-models.sh i9 [--apply]
#   ./cleanup-models.sh macbook-air [--apply]
set -euo pipefail

MACHINE="${1:-}"
[ -n "$MACHINE" ] || { echo "Usage: $0 <i9|macbook-air> [--apply]" >&2; exit 1; }

ARG="${2:-}"
APPLY=0
case "$ARG" in
  "") ;;
  --apply) APPLY=1 ;;
  *) echo "Usage: $0 $MACHINE [--apply]" >&2; exit 1 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_JSON_FILE="${IK_LLAMA_MODELS_JSON:-$SCRIPT_DIR/models.json}"

case "$MACHINE" in
  i9)          MODELS_DIR="${MODELS_DIR:-$HOME/.local/share/llama.cpp/models}" ;;
  probook)
    echo 'WSL is retired on ProBook. Model cleanup runs natively on Windows in $env:USERPROFILE\.local\share\llama.cpp\models.' >&2
    exit 1
    ;;
  macbook-air) MODELS_DIR="${MODELS_DIR:-$HOME/.local/share/llama.cpp/models}" ;;
  *) echo "Usage: $0 <i9|macbook-air> [--apply]" >&2; exit 1 ;;
esac

# Build whitelist from models.json (the one place model lists live) for this machine
active_files=$(MACHINE="$MACHINE" MODELS_JSON_FILE="$MODELS_JSON_FILE" python3 - << 'PYEOF'
import json, os

with open(os.environ['MODELS_JSON_FILE']) as f:
    data = json.load(f)

files = set()
for mode in data.get('machines', {}).get(os.environ['MACHINE'], []):
    files.add(mode['file'])
    if mode.get('mmproj'):
        files.add(mode['mmproj']['file'])

for f in sorted(files):
    print(f)
PYEOF
)

if [ -z "$active_files" ]; then
  echo "Error: Whitelist is empty (failed to parse active models from $MODELS_JSON_FILE for $MACHINE). Refusing to proceed." >&2
  exit 1
fi

echo "Machine:    $MACHINE"
echo "Models dir: $MODELS_DIR"
echo "Whitelist:  $(echo "$active_files" | grep -c . || true) files"
if [ "$APPLY" -eq 0 ]; then
  echo "Dry run — re-run with --apply to remove files."
else
  echo "Removing unlisted GGUF files."
fi
echo

if [ ! -d "$MODELS_DIR" ]; then
  echo "Models directory not found: $MODELS_DIR" >&2
  exit 1
fi

found=0
while IFS= read -r -d '' filepath; do
  filename=$(basename "$filepath")
  [[ "$filename" == *.part ]] && continue
  if ! echo "$active_files" | grep -qxF "$filename" 2>/dev/null; then
    found=1
    size=$(du -h "$filepath" | awk '{print $1}')
    if [ "$APPLY" -eq 0 ]; then
      echo "would remove: $filename ($size)"
    else
      rm -f "$filepath"
      echo "removed: $filename ($size)"
    fi
  fi
done < <(find "$MODELS_DIR" -maxdepth 1 \( -name "*.gguf" -o -name "mmproj-*" \) -print0 2>/dev/null)

echo
if [ "$found" -eq 0 ]; then
  echo "Nothing to remove — models dir matches active lineup."
elif [ "$APPLY" -eq 0 ]; then
  echo "No files removed (dry run)."
fi
