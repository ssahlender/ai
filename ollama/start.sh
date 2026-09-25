#!/usr/bin/env bash
# Starts ollama serve on the MacBook Air M4. Usage: ./start.sh
set -euo pipefail

PORT="${OLLAMA_HOST_PORT:-11434}"

if pgrep -f "ollama serve" >/dev/null 2>&1; then
  echo "ollama serve is already running. Stop it first: ./stop.sh" >&2
  exit 1
fi

# OLLAMA_CONTEXT_LENGTH is NOT optional here — ollama 0.34.4's OpenAI-compatible
# /v1 endpoint SILENTLY IGNORES a per-request `options.num_ctx` (and `keep_alive`).
# Verified on the wire 2026-09-25 with a logging proxy: the request carried
# options={'num_ctx': 16384} keep_alive='30m' while `ollama ps` still reported
# CONTEXT 4096. So every caller that cannot set the context in its own config (e.g.
# graphify, whose derived num_ctx is therefore dead code against /v1) inherits 4096,
# and any prompt whose output needs more room than `4096 - prompt` gets truncated
# mid-answer ("truncated at max_completion_tokens"). Only the server env fixes it.
#
# 16384 costs ~0.68 GB of KV at q8_0 for a 40-layer MoE with 2 KV heads (42.5 KiB per
# token), against ~9 GB free on this 24 GB machine — cheap, and it leaves >12k tokens
# for output. Raise it if a workload needs bigger single calls; the cache is linear.
echo "Starting ollama serve on port $PORT (flash-attention on, q8_0 KV cache, ctx ${OLLAMA_CONTEXT_LENGTH:-16384}, keep-alive ${OLLAMA_KEEP_ALIVE:-30m})..."
exec env \
  OLLAMA_FLASH_ATTENTION=1 \
  OLLAMA_KV_CACHE_TYPE=q8_0 \
  OLLAMA_CONTEXT_LENGTH="${OLLAMA_CONTEXT_LENGTH:-16384}" \
  OLLAMA_KEEP_ALIVE="${OLLAMA_KEEP_ALIVE:-30m}" \
  OLLAMA_HOST="127.0.0.1:$PORT" \
  ollama serve
