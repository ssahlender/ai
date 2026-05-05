#!/usr/bin/env bash
# Downloads models for i9-13900 (64 GB RAM)
set -euo pipefail

export UV_NATIVE_TLS=1
export SSL_CERT_FILE="${SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}"
export REQUESTS_CA_BUNDLE="${REQUESTS_CA_BUNDLE:-/etc/ssl/certs/ca-certificates.crt}"

# ---------------------------------------------------------------------------
# HF_TOKEN: required for gated/private models, optional for public ones.
# Set it in your shell profile so it's never hardcoded here:
#   echo 'export HF_TOKEN=hf_xxxxxxxxxxxxxxxxxxxx' >> ~/.bashrc
#   source ~/.bashrc
# Get your token at: https://huggingface.co/settings/tokens
# ---------------------------------------------------------------------------
HF_TOKEN="${HF_TOKEN:-}"

MODELS_DIR="${MODELS_DIR:-/data/llm/models}"
HF_BASE="https://huggingface.co"

if ! command -v curl >/dev/null 2>&1; then
  echo "curl not found." >&2; exit 1
fi

mkdir -p "$MODELS_DIR"

download_if_missing() {
  local repo="$1" file="$2"
  local dest="$MODELS_DIR/$file"
  if [ -f "$dest" ]; then
    echo "Already present: $file"
    return
  fi

  echo "Downloading $file..."
  local curl_args=(-L --progress-bar --cacert "$SSL_CERT_FILE" -o "$dest")
  if [ -n "$HF_TOKEN" ]; then
    curl_args+=(-H "Authorization: Bearer $HF_TOKEN")
  fi
  curl "${curl_args[@]}" "${HF_BASE}/${repo}/resolve/main/${file}"
}

#
#ls -al /data/llm/models/
#total 101318524
#drwxr-xr-x 3 isc-ssl isc-users        4096 Mai  5 15:57 .
#drwxr-xr-x 4 isc-ssl isc-users        4096 Apr 28 16:09 ..
#drwxr-xr-x 3 isc-ssl isc-users        4096 Apr 28 10:51 .cache
#-rw-r--r-- 1 isc-ssl isc-users 21150362944 Apr 28 11:02 gemma-4-26B-A4B-it-UD-Q5_K_M.gguf
#-rw-r--r-- 1 isc-ssl isc-users 20812953056 Apr 28 12:08 Qwen3.6-27B-Uncensored-HauhauCS-Aggressive-Q5_K_P.gguf
#-rw-r--r-- 1 isc-ssl isc-users 23424536704 Apr 28 16:09 Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q4_K_P.gguf
#-rw-r--r-- 1 isc-ssl isc-users 16796015232 Apr 28 12:11 supergemma4-26b-uncensored-fast-v2-Q4_K_M.gguf
#-rw-r--r-- 1 isc-ssl isc-users 21566252928 Mai  5 12:47 zai-org_GLM-4.7-Flash-Q5_K_M.gguf

# --- Qwen3.6 ---
download_if_missing unsloth/Qwen3.6-27B-GGUF:Q4_K_M Qwen3.6-27B-Q4_K_M.gguf
download_if_missing HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q4_K_P.gguf

# --- Gemma 4 ---
download_if_missing unsloth/gemma-4-26B-A4B-it-GGUF                         gemma-4-26B-A4B-it-UD-Q5_K_M.gguf
download_if_missing Jiunsong/supergemma4-26b-uncensored-gguf-v2              supergemma4-26b-uncensored-fast-v2-Q4_K_M.gguf

# --- GLM-4.7-Flash (30B MoE, ~3B active, DeepSeek2 arch, coding-focused) ---
download_if_missing bartowski/zai-org_GLM-4.7-Flash-GGUF                    zai-org_GLM-4.7-Flash-Q5_K_M.gguf

echo "All models ready in $MODELS_DIR"
