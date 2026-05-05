#!/usr/bin/env bash
# Downloads Qwen3.6 Q3 and Gemma4 IQ4 models for HP ProBook (32 GB RAM).
# Run from WSL2 — files land on the Windows filesystem at /mnt/c/data/llm/models.
set -euo pipefail

MODELS_DIR="${MODELS_DIR:-/mnt/c/data/llm/models}"

if ! command -v hf >/dev/null 2>&1; then
  echo "huggingface-cli not found. Install with: curl -LsSf https://hf.co/cli/install.sh | bash" >&2
  exit 1
fi

mkdir -p "$MODELS_DIR"

download_if_missing() {
  local repo="$1" file="$2"
  if [ -f "$MODELS_DIR/$file" ]; then
    echo "Already present: $file"
  else
    echo "Downloading $file..."
    hf download "$repo" "$file" --local-dir "$MODELS_DIR"
  fi
}

download_if_missing unsloth/Qwen3.6-35B-A3B-GGUF                            Qwen3.6-35B-A3B-UD-Q3_K_M.gguf
download_if_missing HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-IQ4_NL.gguf
download_if_missing unsloth/gemma-4-26B-A4B-it-GGUF                         gemma-4-26B-A4B-it-UD-IQ4_NL.gguf

# --- Qwen3-Coder ---
download_if_missing unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF               Qwen3-Coder-30B-A3B-Instruct-Q3_K_M.gguf

# --- GLM-4.7-Flash (30B MoE, ~3B active, DeepSeek2 arch, coding-focused) ---
download_if_missing bartowski/zai-org_GLM-4.7-Flash-GGUF                    zai-org_GLM-4.7-Flash-Q4_K_M.gguf

echo "All models ready in $MODELS_DIR"
