#!/usr/bin/env bash
# Downloads the latest ik_llama.cpp Windows build for HP ProBook (Ryzen 7 Zen 5).
# Run from WSL2 — files land on the Windows filesystem at /mnt/c/data/llm/ik_llama.
# Skips releases that only have cudart DLL supplements — scans back until a full CPU binary is found.
# Uses generic avx512_vnni_vbmi_bf16 build (not znver5 — znver5 crashes with qwen35moe).
set -euo pipefail

DEST="${IK_LLAMA_DIR:-/mnt/c/data/llm/ik_llama}"
REPO="Thireus/ik_llama.cpp"

find_asset() {
  python3 - <<'PYEOF'
import urllib.request, json, re, sys

repo = "Thireus/ik_llama.cpp"
pattern = re.compile(r"^ik_llama-(?!cudart).+-bin-win-cpu-x64-avx512_vnni_vbmi_bf16\.zip$")
page = 1
while True:
    url = f"https://api.github.com/repos/{repo}/releases?per_page=10&page={page}"
    req = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(req) as resp:
        releases = json.loads(resp.read())
    if not releases:
        break
    for release in releases:
        tag = release["tag_name"]
        for asset in release["assets"]:
            if pattern.match(asset["name"]):
                print(tag, asset["name"])
                sys.exit(0)
    page += 1
sys.exit(1)
PYEOF
}

result=$(find_asset) || { echo "No suitable release found (no CPU binary asset)." >&2; exit 1; }
TAG=$(awk '{print $1}' <<< "$result")
ASSET=$(awk '{print $2}' <<< "$result")

MARKER="$DEST/.tag"
if [ -f "$MARKER" ] && [ "$(cat "$MARKER")" = "$TAG" ]; then
  echo "ik_llama.cpp is already up to date: $TAG"
  exit 0
fi

echo "Found: $ASSET (release $TAG)"
URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET}"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Downloading $ASSET..."
curl -fSL --progress-bar -o "$TMP/$ASSET" "$URL"
mkdir -p "$DEST"
unzip -o "$TMP/$ASSET" -d "$DEST"
printf '%s' "$TAG" > "$MARKER"
echo "Installed ik_llama.cpp $TAG to $DEST"
