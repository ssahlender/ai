#!/usr/bin/env bash
set -euo pipefail

if ! command -v ollama >/dev/null 2>&1; then
  echo "ollama not installed — skipping."
  exit 0
fi

ollama list | awk 'NR > 1 {print $1}' | xargs -r -n1 ollama pull
