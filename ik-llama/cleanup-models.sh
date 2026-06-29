#!/usr/bin/env bash
# Removes model files not in the active start.sh lineup. Dry-run by default.
# Usage:
#   ./cleanup-models.sh i9 [--apply]
#   ./cleanup-models.sh probook [--apply]
#   ./cleanup-models.sh macbook-air [--apply]
set -euo pipefail

MACHINE="${1:-}"
[ -n "$MACHINE" ] || { echo "Usage: $0 <i9|probook|macbook-air> [--apply]" >&2; exit 1; }

ARG="${2:-}"
APPLY=0
case "$ARG" in
  "") ;;
  --apply) APPLY=1 ;;
  *) echo "Usage: $0 $MACHINE [--apply]" >&2; exit 1 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
START_SCRIPT="$SCRIPT_DIR/start.sh"

case "$MACHINE" in
  i9)          MODELS_DIR="${MODELS_DIR:-/data/llm/models}" ;;
  probook)     MODELS_DIR="${MODELS_DIR:-/mnt/c/data/llm/models}" ;;
  macbook-air) MODELS_DIR="${MODELS_DIR:-$HOME/.local/share/llama.cpp/models}" ;;
  *) echo "Usage: $0 <i9|probook|macbook-air> [--apply]" >&2; exit 1 ;;
esac

# Build whitelist by parsing start.sh MODES for this machine
active_files=$(python3 - << PYEOF
import re

machine = "$MACHINE"
with open("$START_SCRIPT") as f:
    content = f.read()

in_block = False
files = set()
for line in content.split('\n'):
    if re.match(r'^\s*' + re.escape(machine) + r'\)\s*$', line):
        in_block = True
        continue
    if in_block and re.match(r'^\s*;;\s*$', line):
        break
    if not in_block:
        continue
    m = re.search(r'"([^"]+)"', line.strip())
    if not m:
        continue
    parts = m.group(1).split('|')
    if len(parts) >= 3 and parts[2].endswith('.gguf'):
        files.add(parts[2])
    if len(parts) >= 8 and parts[7].endswith('.gguf'):
        files.add(parts[7])

for f in sorted(files):
    print(f)
PYEOF
)

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
