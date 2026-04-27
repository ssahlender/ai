#!/usr/bin/env bash
set -euo pipefail

repo="ollama/ollama"
latest_url="https://api.github.com/repos/${repo}/releases/latest"
install_url="https://ollama.com/install.sh"

installed_version() {
  if ! command -v ollama >/dev/null 2>&1; then
    return 1
  fi

  ollama --version | sed -nE 's/.*([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | head -n1
}

latest_version() {
  curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    "$latest_url" |
    sed -nE 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v?([^"]+)".*/\1/p' |
    head -n1
}

install_ollama() {
  curl -fsSL "$install_url" | sh
}

current="$(installed_version || true)"

if [ -z "$current" ]; then
  echo "Ollama is not installed. Installing latest release."
  install_ollama
  exit 0
fi

latest="$(latest_version)"

if [ -z "$latest" ]; then
  echo "Could not determine latest Ollama release from GitHub."
  exit 1
fi

if [ "$(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -n1)" = "$current" ]; then
  echo "Ollama is already up to date: $current"
  exit 0
fi

echo "Updating Ollama from $current to $latest."
install_ollama
