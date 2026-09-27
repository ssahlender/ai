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
  local repo="$1" file="$2" want="${3:-}"
  local dest="$MODELS_DIR/$file"
  if [ -f "$dest" ]; then
    if is_bad_download "$dest"; then
      echo "Removing invalid partial/error download: $file"
      rm -f "$dest"
    elif [ -n "$want" ] && [ "$(wc -c < "$dest" | tr -d ' ')" != "$want" ]; then
      echo "Wrong size for $file, re-downloading"
      rm -f "$dest"
    else
      echo "Already present: $file"
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

  # is_bad_download only catches a download under 1 MB. A truncation above that passes
  # silently, and a half-written 17 GB of weights LOADS and then produces nonsense -
  # which reads as a broken model rather than as a broken download.
  if [ -n "$want" ]; then
    local got; got=$(wc -c < "$tmp" | tr -d ' ')
    if [ "$got" != "$want" ]; then
      rm -f "$tmp"
      echo "Size mismatch for $file: expected $want bytes, got $got" >&2
      exit 1
    fi
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
    download_if_missing Jiunsong/supergemma4-26b-uncensored-gguf-v2               supergemma4-26b-uncensored-fast-v2-Q4_K_M.gguf
    download_if_missing unsloth/Qwen3-Coder-Next-GGUF                             Qwen3-Coder-Next-UD-Q3_K_M.gguf
    download_if_missing HauhauCS/Qwen3.6-27B-Uncensored-HauhauCS-Aggressive       Qwen3.6-27B-Uncensored-HauhauCS-Aggressive-Q5_K_P.gguf
    ;;

  probook)
    MODELS_DIR="${MODELS_DIR:-/mnt/c/data/llm/models}"
    mkdir -p "$MODELS_DIR"

    download_if_missing HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-IQ4_NL.gguf
    download_if_missing unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF               Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf
    ;;

  macbook-air)
    MODELS_DIR="${MODELS_DIR:-$HOME/.local/share/llama.cpp/models}"
    mkdir -p "$MODELS_DIR"
        # ONE model, matching the x86 reference. IQ4_XS (17.44 GiB) is the 4-bit tier that
        # leaves room for a desktop session in 24 GB of unified memory; IQ4_NL is 1 GiB larger.
        # Sizes are exact: an unverified 17 GB download that loads is worse than one that errors.
        download_if_missing HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive  Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-IQ4_XS.gguf  18728777856
        download_if_missing HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive  mmproj-Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-f16.gguf  899283072
    ;;

  *) usage ;;
esac

echo "All models ready in $MODELS_DIR"
