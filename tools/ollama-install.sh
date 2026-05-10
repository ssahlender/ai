#!/usr/bin/env bash
set -euo pipefail

# Skip on i9 (company proxy) — CPU-only Ollama is too slow. Use ik_llama.cpp.
if [[ -n "${http_proxy:-}${HTTP_PROXY:-}${https_proxy:-}${HTTPS_PROXY:-}" ]]; then
  echo "Skipping on i9 — Ollama is too slow on CPU. Use ik_llama.cpp."
  exit 0
fi

brew install ollama
