#!/usr/bin/env bash
# Quick MLX throughput test on the MacBook Air M4.
# Usage: ./bench.sh <hf-repo> [max-tokens]
set -euo pipefail

REPO="${1:-}"
MAX_TOKENS="${2:-256}"
PROMPT="${MLX_BENCH_PROMPT:-Explain the difference between a MoE and a dense transformer model in three sentences.}"

if [ -z "$REPO" ]; then
  echo "Usage: $0 <hf-repo> [max-tokens]" >&2
  echo "  e.g. $0 mlx-community/Qwen3-30B-A3B-Instruct-2507-4bit" >&2
  exit 1
fi

echo "== $REPO (max-tokens=$MAX_TOKENS) =="
mlx_lm.generate \
  --model "$REPO" \
  --prompt "$PROMPT" \
  --max-tokens "$MAX_TOKENS"
