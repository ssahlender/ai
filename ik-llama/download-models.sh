#!/usr/bin/env bash
# Downloads GGUF models + mmproj files for all machines.
# Usage: ./download-models.sh [i9|probook|macbook-air]
set -euo pipefail

MACHINE="${1:-}"

usage() {
  echo "Usage: $0 [i9|probook|macbook-air]" >&2
  exit 1
}

[ -n "$MACHINE" ] || usage

# ── shared helpers ────────────────────────────────────────────────
HF_BASE="https://huggingface.co"
HF_TOKEN="${HF_TOKEN:-}"

is_bad_download() {
  local file="$1" size
  size=$(wc -c < "$file")
  [ "$size" -lt 1048576 ]
}

download_if_missing() {
  local repo="$1" file="$2"
  local dest="$MODELS_DIR/$file"
  if [ -f "$dest" ]; then
    if is_bad_download "$dest"; then
      echo "Removing invalid partial/error download: $file"
      rm -f "$dest"
    else
      echo "Already present: $file"
      return
    fi
  fi

  local tmp="$dest.part"
  [ -f "$tmp" ] && rm -f "$tmp"

  echo "Downloading $file..."
  local curl_args=(-fL --progress-bar -o "$tmp")
  [ -n "${SSL_CERT_FILE:-}" ] && curl_args+=(--cacert "$SSL_CERT_FILE")
  [ -n "$HF_TOKEN" ] && curl_args+=(-H "Authorization: Bearer $HF_TOKEN")

  if ! curl "${curl_args[@]}" "${HF_BASE}/${repo}/resolve/main/${file}"; then
    rm -f "$tmp"
    echo "Download failed: ${HF_BASE}/${repo}/resolve/main/${file}" >&2
    exit 1
  fi

  if is_bad_download "$tmp"; then
    rm -f "$tmp"
    echo "Downloaded file looks like an error page, not a GGUF: $file" >&2
    exit 1
  fi

  mv "$tmp" "$dest"
}

# ── machine setup ─────────────────────────────────────────────────
case "$MACHINE" in
  i9)
    MODELS_DIR="${MODELS_DIR:-/data/llm/models}"
    export SSL_CERT_FILE="${SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}"
    export REQUESTS_CA_BUNDLE="${REQUESTS_CA_BUNDLE:-/etc/ssl/certs/ca-certificates.crt}"
    export UV_NATIVE_TLS=1
    mkdir -p "$MODELS_DIR"

    download_if_missing HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive  Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q6_K_P.gguf
    download_if_missing HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive  mmproj-Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-f16.gguf
    download_if_missing Jackrong/Qwopus3.6-35B-A3B-v1-GGUF                       Qwopus3.6-35B-A3B-v1-Q5_K_M.gguf
    download_if_missing Jackrong/Qwopus3.6-35B-A3B-v1-GGUF                       mmproj-F32.gguf
    download_if_missing deepreinforce-ai/Ornith-1.0-35B-GGUF                      ornith-1.0-35b-Q6_K.gguf
    download_if_missing Jiunsong/supergemma4-26b-uncensored-gguf-v2               supergemma4-26b-uncensored-fast-v2-Q4_K_M.gguf
    download_if_missing unsloth/Qwen3-Coder-Next-GGUF                             Qwen3-Coder-Next-UD-Q3_K_M.gguf
    ;;

  probook)
    MODELS_DIR="${MODELS_DIR:-/mnt/c/data/llm/models}"
    mkdir -p "$MODELS_DIR"

    download_if_missing HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-IQ4_NL.gguf
    download_if_missing deepreinforce-ai/Ornith-1.0-35B-GGUF                    ornith-1.0-35b-Q4_K_M.gguf
    download_if_missing bartowski/zai-org_GLM-4.7-Flash-GGUF                    zai-org_GLM-4.7-Flash-Q4_K_M.gguf
    ;;

  macbook-air)
    MODELS_DIR="${MODELS_DIR:-$HOME/.local/share/llama.cpp/models}"
    mkdir -p "$MODELS_DIR"

    download_if_missing HauhauCS/Qwen3.6-27B-Uncensored-HauhauCS-Aggressive  Qwen3.6-27B-Uncensored-HauhauCS-Aggressive-IQ4_XS.gguf
    download_if_missing HauhauCS/Qwen3.6-27B-Uncensored-HauhauCS-Aggressive  mmproj-Qwen3.6-27B-Uncensored-HauhauCS-Aggressive-f16.gguf
    download_if_missing HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive  Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-IQ4_NL.gguf
    download_if_missing HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive  mmproj-Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-f16.gguf
    ;;

  *) usage ;;
esac

echo "All models ready in $MODELS_DIR"
