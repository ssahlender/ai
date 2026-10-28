#!/usr/bin/env bash
# stop.sh — stop the Mac stack: local-proxy, llama-swap, ollama serve and any loaded model runner
set -euo pipefail
pkill -f "local-proxy.py" 2>/dev/null && echo "local-proxy stopped" || echo "local-proxy not running"
pkill -x llama-swap 2>/dev/null && echo "llama-swap stopped" || echo "llama-swap not running"
pkill -f "ollama serve" 2>/dev/null && echo "ollama serve stopped" || echo "ollama serve not running"
pkill -9 -f "ollama runner" 2>/dev/null && echo "ollama runner killed" || true
