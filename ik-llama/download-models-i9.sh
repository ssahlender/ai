#!/usr/bin/env bash
# Downloads Qwen3.6 Q4 and Gemma4 Q5 models for i9-13900 (64 GB RAM)
set -euo pipefail

export UV_NATIVE_TLS=1
export SSL_CERT_FILE="${SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}"
export REQUESTS_CA_BUNDLE="${REQUESTS_CA_BUNDLE:-/etc/ssl/certs/ca-certificates.crt}"

MODELS_DIR="${MODELS_DIR:-/data/llm/models}"

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

# --- Qwen3.5 ---
download_if_missing unsloth/Qwen3.5-27B-GGUF                          Qwen3.5-27B-Q4_K_M.gguf

# --- Qwen3.6 ---
download_if_missing unsloth/Qwen3.6-35B-A3B-GGUF                      Qwen3.6-35B-A3B-UD-Q4_K_M.gguf
download_if_missing HauhauCS/Qwen3.6-27B-Uncensored-HauhauCS-Aggressive Qwen3.6-27B-Uncensored-HauhauCS-Aggressive-Q5_K_P.gguf

# --- Gemma 4 ---
download_if_missing unsloth/gemma-4-26B-A4B-it-GGUF                   gemma-4-26B-A4B-it-UD-Q5_K_M.gguf
download_if_missing Jiunsong/supergemma4-26b-uncensored-gguf-v2        supergemma4-26b-uncensored-fast-v2-Q4_K_M.gguf

echo "All models ready in $MODELS_DIR"
