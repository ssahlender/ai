#!/usr/bin/env bash
# Stop the local model stack on the i9 or the Mac, however it was started (chain or bare server).
# --all also stops the cloud proxies tools/claude-providers.sh starts (ocg-proxy 4099, nvidia-proxy 4098).
# Usage: ./stop.sh [--all]          (the ProBook: probook\stop-llm.ps1)
set -euo pipefail

LLM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=shared/common.sh
source "$LLM_DIR/shared/common.sh"
MACHINE=$(python3 "$LLM_DIR/shared/models.py" machine) || exit 1

stop_port "${IK_LLAMA_AGENT_PORT:-9081}" "local-proxy"
stop_port "${IK_LLAMA_SWAP_PORT:-9082}" "llama-swap"     # SIGTERM: it stops the model it loaded
case "$MACHINE" in
  i9)
    sleep 1   # give llama-swap a moment to stop its own llama-server first
    pkill -x llama-server 2>/dev/null && echo "llama-server stopped" || echo "llama-server not running" ;;
  mac)
    stop_port "${OLLAMA_HOST_PORT:-11434}" "ollama serve"
    pkill -9 -f "ollama runner" 2>/dev/null && echo "ollama runner killed" || true ;;
esac
if [ "${1:-}" = "--all" ]; then
  stop_port 4099 "ocg-proxy"
  stop_port 4098 "nvidia-proxy"
fi
