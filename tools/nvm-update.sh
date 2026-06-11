#!/usr/bin/env bash
# Updates nvm via Homebrew and installs the latest LTS Node. Skipped on i9 (work provides Node).
set -euo pipefail

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-i9.sh"
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_brew-wrapper.sh"

if [ -n "$IS_I9" ]; then
  echo "Skipping on i9 — work provides its own Node stack."
  exit 0
fi

if $BREW list nvm &>/dev/null; then
  $BREW upgrade nvm || true
else
  echo "nvm not installed — skipping"
  exit 0
fi

export NVM_DIR="$HOME/.nvm"
# shellcheck source=/dev/null
[ -s "$(brew --prefix)/opt/nvm/nvm.sh" ] && . "$(brew --prefix)/opt/nvm/nvm.sh"

if ! command -v nvm &>/dev/null; then
  echo "nvm not available — run nvm-install.sh first." >&2
  exit 1
fi

nvm install --lts --reinstall-packages-from=current
nvm alias default lts/*
nvm use default

npm install -g npm@latest
npm update -g

cleanup_old_node_versions() {
  local keep_extra="${NVM_KEEP_OLD_VERSIONS:-0}"
  local versions_dir="$NVM_DIR/versions/node"
  local current_version default_version
  local -a keep versions
  local version keep_version should_keep

  if ! [[ "$keep_extra" =~ ^[0-9]+$ ]]; then
    echo "NVM_KEEP_OLD_VERSIONS must be a non-negative integer, got: $keep_extra" >&2
    return 1
  fi

  [ -d "$versions_dir" ] || return 0

  current_version="$(nvm current)"
  default_version="$(nvm version default 2>/dev/null || true)"
  keep=("$current_version")
  if [[ "$default_version" == v* ]]; then
    keep+=("$default_version")
  fi

  while IFS= read -r version; do
    versions+=("$version")
  done < <(
    find "$versions_dir" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; |
      python3 -c '
import re
import sys

def key(version):
    return tuple(int(part) for part in re.findall(r"\d+", version))

for item in sorted((line.strip() for line in sys.stdin if line.strip()), key=key, reverse=True):
    print(item)
'
  )
  for version in "${versions[@]}"; do
    if [ "$keep_extra" -le 0 ]; then
      break
    fi
    keep+=("$version")
    keep_extra=$((keep_extra - 1))
  done

  for version in "${versions[@]}"; do
    should_keep=0
    for keep_version in "${keep[@]}"; do
      if [ "$version" = "$keep_version" ]; then
        should_keep=1
        break
      fi
    done
    if [ "$should_keep" -eq 0 ]; then
      echo "Removing old Node version: $version"
      nvm uninstall "$version"
    fi
  done

  nvm cache clear
}

cleanup_old_node_versions

node -v && npm -v && npx -v
