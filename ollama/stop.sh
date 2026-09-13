#!/usr/bin/env bash
# stop.sh — stop ollama serve and any loaded model runner
set -euo pipefail
pkill -f "ollama serve" 2>/dev/null && echo "ollama serve stopped" || echo "ollama serve not running"
pkill -9 -f "ollama runner" 2>/dev/null && echo "ollama runner killed" || true
