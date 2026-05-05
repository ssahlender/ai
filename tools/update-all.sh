#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

run() {
  echo "==> $*"
  "$@"
}

#run ./ollama-update.sh
#run ./ollama-models-update.sh
run ./nvm-update.sh
run ./claude-update.sh
run ./opencode-update.sh
run ./codex-update.sh
run ./hf-update.sh
