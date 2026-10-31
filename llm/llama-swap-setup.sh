#!/usr/bin/env bash
# Start the default chain on the i9 or the Mac (the ProBook: probook\llama-swap-setup.ps1):
#   agents -> local-proxy.py :9081 -> llama-swap :9082 (web UI, stats) -> engine
# i9: llama-swap starts llama-server itself, per model, through i9/start.sh.
# Mac: Ollama is started first if it is not up; llama-swap forwards to it and turns thinking off.
# The config comes from models.json via shared/llama_swap_config.py. Stop everything: ./stop.sh
# Usage: ./llama-swap-setup.sh    (LLM_MACHINE=i9|mac overrides the machine detection)
# Everything listens on 127.0.0.1 only. To share the models with the home gateway: ./share.sh
set -euo pipefail

LLM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=shared/common.sh
source "$LLM_DIR/shared/common.sh"
MACHINE=$(python3 "$LLM_DIR/shared/models.py" machine) || exit 1
[ "$MACHINE" != probook ] || { echo "On the ProBook use probook\\llama-swap-setup.ps1" >&2; exit 1; }
SWAP_PORT="${IK_LLAMA_SWAP_PORT:-9082}"
AGENT_PORT="${IK_LLAMA_AGENT_PORT:-9081}"
OLLAMA_PORT="${OLLAMA_HOST_PORT:-11434}"
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/llama-swap/config.yaml"
LOG_DIR="${TMPDIR:-/tmp}"

LLAMA_SWAP_BIN="${LLAMA_SWAP_BIN:-$(find_bin llama-swap || true)}"
[ -n "$LLAMA_SWAP_BIN" ] || { echo "llama-swap not found. Install: ../tools/llama-swap-install.sh" >&2; exit 1; }

if [ "$MACHINE" = mac ] && ! curl -sf "http://127.0.0.1:$OLLAMA_PORT/api/version" >/dev/null 2>&1; then
  echo "Starting Ollama ..."
  nohup "$LLM_DIR/mac/start.sh" >"$LOG_DIR/ollama.log" 2>&1 &
  disown
  wait_http "http://127.0.0.1:$OLLAMA_PORT/api/version" 60 || { echo "Ollama did not come up; see $LOG_DIR/ollama.log" >&2; exit 1; }
fi

mkdir -p "$(dirname "$CONFIG_FILE")"
python3 "$LLM_DIR/shared/llama_swap_config.py" --machine "$MACHINE" > "$CONFIG_FILE.new"
mv "$CONFIG_FILE.new" "$CONFIG_FILE"
"$LLAMA_SWAP_BIN" -config "$CONFIG_FILE" -validate
echo "Wrote $CONFIG_FILE ($MACHINE)"

if [ -n "$(pids_on_port "$SWAP_PORT")" ]; then
  echo "llama-swap already running on $SWAP_PORT (for a new config: ./stop.sh && ./llama-swap-setup.sh)"
else
  nohup "$LLAMA_SWAP_BIN" -config "$CONFIG_FILE" -listen "127.0.0.1:$SWAP_PORT" >"$LOG_DIR/llama-swap.log" 2>&1 &
  disown
  wait_http "http://127.0.0.1:$SWAP_PORT/v1/models" || { echo "llama-swap did not come up; see $LOG_DIR/llama-swap.log" >&2; exit 1; }
fi

# local-proxy in front, pointed at llama-swap (replacing one a bare start.sh pointed at 9080)
stop_port "$AGENT_PORT" "previous local-proxy" >/dev/null
sleep 0.3
LOCAL_PROXY_UPSTREAM="http://127.0.0.1:$SWAP_PORT" LOCAL_PROXY_PORT="$AGENT_PORT" \
  nohup python3 "$LLM_DIR/shared/local-proxy.py" >"$LOG_DIR/local-proxy.log" 2>&1 &
disown
wait_http "http://127.0.0.1:$AGENT_PORT/proxy-health" || { echo "local-proxy did not come up; see $LOG_DIR/local-proxy.log" >&2; exit 1; }

echo
echo "Agents:  http://127.0.0.1:$AGENT_PORT/v1   (wired by ./setup-agents.sh)"
echo "Web UI:  http://127.0.0.1:$SWAP_PORT/ui   (Playground: chat with the models)"
