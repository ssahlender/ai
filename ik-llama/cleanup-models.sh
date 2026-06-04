#!/usr/bin/env bash
# Removes rejected/obsolete GGUF model files. Dry-run by default.
# Usage:
#   ./cleanup-models.sh i9          # show what would be removed
#   ./cleanup-models.sh i9 --apply  # actually remove files
set -euo pipefail

MACHINE="${1:-}"

[ -n "$MACHINE" ] || { echo "Usage: $0 <i9> [--apply]" >&2; exit 1; }

ARG="${2:-}"
APPLY=0
case "$ARG" in
  "") ;;
  --apply) APPLY=1 ;;
  *) echo "Usage: $0 $MACHINE [--apply]" >&2; exit 1 ;;
esac

case "$MACHINE" in
  probook|macbook-air)
    echo "No obsolete models configured for $MACHINE. Nothing to clean." >&2
    exit 0
    ;;
  i9)
    MODELS_DIR="${MODELS_DIR:-/data/llm/models}"
    obsolete_models=(
      "Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q4_K_P.gguf"
      "Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q5_K_P.gguf"
      "Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q8_K_P.gguf"
      "Qwen3-32B-Q5_K_M.gguf"
      "Qwen3-32B-Q4_K_M.gguf"
      "Qwen3-14B-Q5_K_M.gguf"
      "Qwen3-14B-Q4_K_M.gguf"
      "Qwen3-8B-Q5_K_M.gguf"
      "Qwen3-8B-Q4_K_M.gguf"
      "Qwen2.5-Coder-32B-Instruct-Q5_K_M.gguf"
      "Qwen2.5-Coder-32B-Instruct-Q4_K_M.gguf"
      "qwen2.5-coder-32b-instruct-q5_k_m.gguf"
      "qwen2.5-coder-32b-instruct-q4_k_m.gguf"
      "Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf"
      "Qwen3-Coder-30B-A3B-Instruct-Q3_K_M.gguf"
      "Qwen3-Coder-30B-A3B-Instruct-Q5_K_M.gguf"
      "Qwen3-Coder-30B-A3B-Instruct-Q6_K.gguf"
      "Qwen3-Coder-30B-A3B-Instruct-Q8_0.gguf"
    )
    ;;
  *) echo "Usage: $0 <i9> [--apply]" >&2; exit 1 ;;
esac

echo "Model directory: $MODELS_DIR"
if [ "$APPLY" -eq 0 ]; then
  echo "Dry run. Re-run with --apply to remove these files."
else
  echo "Removing obsolete GGUF files."
fi
echo

found=0
for file in "${obsolete_models[@]}"; do
  path="$MODELS_DIR/$file"
  if [ ! -e "$path" ]; then
    echo "missing: $file"
    continue
  fi

  found=1
  size=$(du -h "$path" | awk '{print $1}')
  if [ "$APPLY" -eq 0 ]; then
    echo "would remove: $file ($size)"
  else
    rm -f "$path"
    echo "removed: $file ($size)"
  fi
done

echo
if [ "$found" -eq 0 ]; then
  echo "No obsolete GGUF files found."
elif [ "$APPLY" -eq 0 ]; then
  echo "No files removed."
fi
