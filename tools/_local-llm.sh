# _local-llm.sh — sourced by claude-providers.sh and docker-agent-providers.sh: find the local model.
# The default chain is local-proxy (9081) -> llama-swap (9082) -> server; a bare llama-server is 9080.

llama_host() {
  echo "${IK_LLAMA_HOST:-127.0.0.1}"
}

# llama-swap's port when it answers, else the bare llama-server's.
local_upstream_port() {
  local swap="${IK_LLAMA_SWAP_PORT:-9082}"
  if curl -sf --max-time 2 --connect-timeout 1 "http://$(llama_host):${swap}/v1/models" >/dev/null 2>&1; then
    echo "$swap"
  else
    echo "${IK_LLAMA_PORT:-9080}"
  fi
}

detect_local() {
  local model host port
  port=$(local_upstream_port)
  host=$(llama_host)
  model=$(curl -sf --max-time 3 --connect-timeout 2 "http://${host}:${port}/v1/models" 2>/dev/null | \
          python3 -c "
import sys, json, os
d = json.load(sys.stdin)
full = d['data'][0]['id']
# strip path prefix and .gguf suffix to get the model stem
name = os.path.basename(full)
if name.endswith('.gguf'):
    name = name[:-5]
print(name)
" 2>/dev/null || true)
  if [ -n "$model" ]; then
    echo "$model"
    return
  fi
  echo ""
}

detect_local_ctx() {
  local host port
  port=$(local_upstream_port)
  host=$(llama_host)
  curl -sf --max-time 3 --connect-timeout 2 "http://${host}:${port}/props" 2>/dev/null | \
    python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('default_generation_settings', {}).get('n_ctx', ''))
" 2>/dev/null || true
}
