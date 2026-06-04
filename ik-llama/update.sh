#!/usr/bin/env bash
# Updates ik_llama.cpp (Linux/Windows) or llama.cpp (macOS via brew).
# Usage: ./update.sh <i9|probook|macbook-air>
set -euo pipefail

MACHINE="${1:-}"

[ -n "$MACHINE" ] || { echo "Usage: $0 <i9|probook|macbook-air>" >&2; exit 1; }

case "$MACHINE" in
  i9)
    export SSL_CERT_FILE="${SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}"
    export REQUESTS_CA_BUNDLE="${REQUESTS_CA_BUNDLE:-/etc/ssl/certs/ca-certificates.crt}"
    export UV_NATIVE_TLS=1
    DEST="${IK_LLAMA_DIR:-/data/llm/ik_llama}"
    REPO="Thireus/ik_llama.cpp"
    ARCH_PATTERN='^ik_llama-(?!cudart).+-bin-ubuntu-x64-avx2\.zip$'
    ;;

  probook)
    DEST="${IK_LLAMA_DIR:-/mnt/c/data/llm/ik_llama}"
    REPO="Thireus/ik_llama.cpp"
    ARCH_PATTERN='^ik_llama-(?!cudart).+-bin-win-cpu-x64-avx512_vnni_vbmi_bf16\.zip$'
    ;;

  macbook-air)
    if ! command -v brew >/dev/null 2>&1; then
      echo "brew not found. Install from https://brew.sh" >&2
      exit 1
    fi
    brew upgrade llama.cpp
    echo "llama.cpp updated."
    exit 0
    ;;

  *) echo "Usage: $0 <i9|probook|macbook-air>" >&2; exit 1 ;;
esac

# ── find latest release asset matching the arch pattern ────────────
find_asset() {
  python3 - "$ARCH_PATTERN" "$REPO" << 'PYEOF'
import urllib.request, json, re, sys

pattern = re.compile(sys.argv[1])
repo = sys.argv[2]
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

ARCH_PATTERN="$ARCH_PATTERN" REPO="$REPO" result=$(find_asset) || { echo "No suitable release found." >&2; exit 1; }
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
