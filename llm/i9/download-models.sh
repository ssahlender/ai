#!/usr/bin/env bash
# Downloads GGUF models + mmproj files for all machines.
# Usage: ./download-models.sh i9
set -euo pipefail

MACHINE="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="$(cd "$SCRIPT_DIR/../shared" && pwd)"

usage() {
  echo "Usage: $0 i9" >&2
  exit 1
}

[ -n "$MACHINE" ] || usage

# ── shared helpers ────────────────────────────────────────────────
HF_BASE="https://huggingface.co"
HF_TOKEN="${HF_TOKEN:-}"

# Unauthenticated HF downloads hit a lower rate limit (429s on repeated/parallel pulls).
# `hf auth login` (or the older `huggingface-cli login`) already saved a token for this
# exact purpose; use it instead of making every run export HF_TOKEN by hand.
if [ -z "$HF_TOKEN" ]; then
  _hf_token_file="${HF_HOME:-$HOME/.cache/huggingface}/token"
  if [ -f "$_hf_token_file" ]; then
    HF_TOKEN="$(tr -d '[:space:]' < "$_hf_token_file")"
    [ -n "$HF_TOKEN" ] && echo "Using HF token from $_hf_token_file"
  fi
  unset _hf_token_file
fi

is_bad_download() {
  local file="$1" size
  size=$(wc -c < "$file")
  [ "$size" -lt 1048576 ]
}

# download_if_missing <hf-repo> <remote-file> [expected-bytes] [local-name]
# local-name saves under a different name (used where two repos ship the same file name).
download_if_missing() {
  local repo="$1" file="$2" want="${3:-}" local_name="${4:-$2}"
  local dest="$MODELS_DIR/$local_name"
  if [ -f "$dest" ]; then
    if is_bad_download "$dest"; then
      echo "Removing invalid partial/error download: $file"
      rm -f "$dest"
    elif [ -n "$want" ] && [ "$(wc -c < "$dest" | tr -d ' ')" != "$want" ]; then
      echo "Wrong size for $file, re-downloading"
      rm -f "$dest"
    else
      echo "Already present: $file"
      return 0
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

# preflight_disk_space <local-name> <expected-bytes> [<local-name> <expected-bytes> ...]
# Sums only the files that are actually missing or wrong-size (not the whole lineup), and
# refuses before starting rather than discovering a full disk partway through a 20+ GB
# download. Only meaningful where every file has a known expected size (i9 below); skipped
# for machines where it doesn't.
preflight_disk_space() {
  local needed=0 name want dest have avail margin=2147483648
  while [ $# -ge 2 ]; do
    name="$1" want="$2"; shift 2
    dest="$MODELS_DIR/$name"
    if [ -f "$dest" ]; then
      have=$(wc -c < "$dest" | tr -d ' ')
      [ "$have" = "$want" ] && continue
    fi
    needed=$((needed + want))
  done
  [ "$needed" -eq 0 ] && return 0
  avail=$(df --output=avail -B1 "$MODELS_DIR" 2>/dev/null | tail -1 | tr -d ' ')
  if [ -z "$avail" ]; then
    echo "Could not read free disk space for $MODELS_DIR; skipping the preflight check." >&2
    return 0
  fi
  echo "Preflight: $(( (needed + 1073741823) / 1073741824 )) GiB left to download, $(( avail / 1073741824 )) GiB free at $MODELS_DIR."
  if [ "$avail" -lt $((needed + margin)) ]; then
    echo "Not enough free disk space: need ~$(( (needed + 1073741823) / 1073741824 )) GiB (+2 GiB margin)," \
         "only $(( avail / 1073741824 )) GiB free. Free up space or point MODELS_DIR elsewhere." >&2
    exit 1
  fi
}

# ── machine setup ─────────────────────────────────────────────────
case "$MACHINE" in
  i9)
    MODELS_DIR="${MODELS_DIR:-$HOME/.local/share/llama.cpp/models}"
    export SSL_CERT_FILE="${SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}"
    export REQUESTS_CA_BUNDLE="${REQUESTS_CA_BUNDLE:-/etc/ssl/certs/ca-certificates.crt}"
    export UV_NATIVE_TLS=1
    ;;
  *) usage ;;
esac
mkdir -p "$MODELS_DIR"

# ── one row per downloadable file (model + its mmproj, if any), from models.json via models.py ──
ENTRIES=$(python3 "$SHARED_DIR/models.py" downloads "$MACHINE")
[ -n "$ENTRIES" ] || { echo "No models for '$MACHINE' in $(python3 "$SHARED_DIR/models.py" path)." >&2; exit 1; }

PREFLIGHT_ARGS=()
while IFS=$'\t' read -r local_name _repo _repo_file bytes; do
  [ -n "$bytes" ] && PREFLIGHT_ARGS+=("$local_name" "$bytes")
done <<< "$ENTRIES"
[ "${#PREFLIGHT_ARGS[@]}" -gt 0 ] && preflight_disk_space "${PREFLIGHT_ARGS[@]}"

while IFS=$'\t' read -r local_name repo repo_file bytes; do
  download_if_missing "$repo" "$repo_file" "$bytes" "$local_name"
done <<< "$ENTRIES"

echo "All models ready in $MODELS_DIR"
