#!/usr/bin/env bash
# Downloads the latest ik_llama.cpp Windows build for HP ProBook (Ryzen 7 Zen 5).
# Run from WSL2 — files land on the Windows filesystem at /mnt/c/data/llm/ik_llama.
set -euo pipefail

DEST="${IK_LLAMA_DIR:-/mnt/c/data/llm/ik_llama}"
REPO="Thireus/ik_llama.cpp"
ASSET_SUFFIX="bin-win-cpu-x64-avx512_vnni_vbmi_bf16"

latest_tag() {
  local json
  json=$(curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${REPO}/releases/latest")
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq -r '.tag_name'
  else
    printf '%s' "$json" | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])"
  fi
}

TAG=$(latest_tag)

if [ -z "$TAG" ]; then
  echo "Could not determine latest ik_llama.cpp release." >&2
  exit 1
fi

MARKER="$DEST/.tag"
if [ -f "$MARKER" ] && [ "$(cat "$MARKER")" = "$TAG" ]; then
  echo "ik_llama.cpp is already up to date: $TAG"
  exit 0
fi

ASSET="ik_llama-${TAG}-${ASSET_SUFFIX}.zip"
URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET}"

echo "Downloading $ASSET..."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

curl -fSL --progress-bar -o "$TMP/$ASSET" "$URL"
mkdir -p "$DEST"
unzip -o "$TMP/$ASSET" -d "$DEST"
printf '%s' "$TAG" > "$MARKER"
echo "Installed ik_llama.cpp $TAG to $DEST"
