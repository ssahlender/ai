#!/usr/bin/env bash
# Starts a SECOND, extraction-only ollama serve on its own port.
#
# Why a second instance instead of the main one: ollama 0.34.4's OpenAI-compatible
# /v1 endpoint SILENTLY IGNORES a per-request `options.num_ctx` and `keep_alive`
# (verified on the wire 2026-09-25 with a logging proxy: the request carried
# options={'num_ctx': 16384} keep_alive='30m' while `ollama ps` reported CONTEXT 4096).
# The only lever is the server environment, which is global to the instance — so a
# dedicated instance raises the context for extraction WITHOUT touching the context or
# memory profile of the daily-driver instance (whose other model's KV cost is
# unmeasured and possibly fp16-sized at 64 layers).
#
# Sizing for the extraction model (qwen3.6:35b-a3b MoE, 40 layers, 2 KV heads,
# 256-dim heads, q8_0 KV = 42.5 KiB per token of context, measured): 16384 costs
# ~0.68 GB. The daily-driver model is untouched by this.
set -euo pipefail

PORT="${GRAPHIFY_OLLAMA_PORT:-11438}"

# Resolve the binary explicitly: this script is started from non-interactive sessions
# (ssh) where Homebrew's bin directory is not on PATH.
OLLAMA_BIN="$(command -v ollama 2>/dev/null || true)"
if [ -z "$OLLAMA_BIN" ]; then
  for cand in /opt/homebrew/bin/ollama /usr/local/bin/ollama /usr/bin/ollama; do
    [ -x "$cand" ] && OLLAMA_BIN="$cand" && break
  done
fi
if [ -z "$OLLAMA_BIN" ] || [ ! -x "$OLLAMA_BIN" ]; then
  echo "could not find the ollama binary (looked in PATH and the usual prefixes)" >&2
  exit 1
fi

if curl -s -m 2 "http://127.0.0.1:$PORT/api/version" >/dev/null 2>&1; then
  echo "an ollama instance is already listening on $PORT. Stop it first: ./stop-graphify.sh" >&2
  exit 1
fi

echo "Starting the extraction-only ollama serve on port $PORT (ctx ${OLLAMA_CONTEXT_LENGTH:-16384}, keep-alive ${OLLAMA_KEEP_ALIVE:-5m}, num_parallel ${OLLAMA_NUM_PARALLEL:-1})..."
exec env \
  OLLAMA_FLASH_ATTENTION=1 \
  OLLAMA_KV_CACHE_TYPE=q8_0 \
  OLLAMA_CONTEXT_LENGTH="${OLLAMA_CONTEXT_LENGTH:-16384}" \
  OLLAMA_KEEP_ALIVE="${OLLAMA_KEEP_ALIVE:-5m}" \
  OLLAMA_NUM_PARALLEL="${OLLAMA_NUM_PARALLEL:-1}" \
  OLLAMA_HOST="127.0.0.1:$PORT" \
  "$OLLAMA_BIN" serve
