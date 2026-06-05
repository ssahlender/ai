# AI Agent Configuration

How to wire OpenCode and Claude Code to the local ik_llama.cpp server.

## OpenCode

Run the setup script for your machine — it parses `start.sh` for model mappings and generates the provider config dynamically. Only models whose GGUF files exist on disk are included. Vision models automatically get `modalities` for image input. OpenCode config is written only when `opencode` is installed.

```bash
# ProBook (WSL2)
./setup-agents.sh probook

# i9
./setup-agents.sh i9

# MacBook Air
./setup-agents.sh macbook-air
```

The ProBook script auto-detects the Windows host IP from the WSL2 default gateway. The generated config uses `http://<host-ip>:9080/v1` (all machines).

Model shortnames are derived from `start.sh` case entries. Run `setup-agents.sh` to see available shortnames — they're printed after install. No static config file to maintain.

## Pi

The same setup scripts also write `~/.pi/agent/models.json` when `pi` is
installed. The Pi provider key is `ik-llama`; model IDs match the start-script
shortnames such as `qwen36u35bq6kp`.

### Large tool writes

With local ik_llama.cpp/OpenCode, avoid generating large files directly inside
one write/edit tool call. This is especially important for draw.io XML, SVG, and
large JSON, where malformed escaping or truncation can produce errors like
`JSON Parse error: unterminated string`.

Instead, create a compact generator script or structured source file, run it to
write the large artifact, then validate the output. For draw.io, generate the
`.drawio` XML from data in a script rather than inlining the full XML payload in
the tool call.

## Claude Code

Use `claude-providers.sh` to pick local or remote models interactively. Type
numbers to select — no typing model names:

```bash
# Interactive picker (local + OpenRouter + NVIDIA + OpenCode Go + Proxy)
./claude-providers.sh

# Direct launch (skip picker)
./claude-providers.sh local                      # auto-detects running model
./claude-providers.sh openrouter anthropic/claude-sonnet-4
./claude-providers.sh nvidia nvidia/llama-4-maverick
./claude-providers.sh opencode-go qwen3.7-max
./claude-providers.sh opencode-proxy deepseek-v4-pro
```

The script sources `~/.secrets` for API keys. Copy the template and
fill in your keys:

```bash
cp .secrets.example ~/.secrets && chmod 600 ~/.secrets
```

```bash
# ~/.secrets
export OPENROUTER_API_KEY=sk-or-v1-xxxxx
export NVIDIA_API_KEY=nvapi-xxxxx
export OPENCODE_GO_API_KEY=oc-xxxxx
```

### Proxy (ocg-proxy.py)

`opencode-proxy` auto-starts `ocg-proxy.py` (port 4099) which translates
Anthropic Messages → OpenAI Chat Completions. This unlocks OpenCode Go's
OpenAI-only models (DeepSeek, Kimi, GLM) for use with Claude Code.

You can also start the proxy standalone and leave it running:

```bash
# Start proxy (keep it running in background)
export OCG_PROXY_API_KEY=$OPENCODE_GO_API_KEY
./ocg-proxy.py &

# Then any Claude Code session points at it:
ANTHROPIC_BASE_URL=http://localhost:4099 \
ANTHROPIC_CUSTOM_MODEL_OPTION=deepseek-v4-pro \
ANTHROPIC_API_KEY=dummy \
claude --bare --model deepseek-v4-pro
```

Supports `OCG_PROXY_PORT`, `OCG_PROXY_MODELS` (comma-separated), and
`SSL_CERT_FILE` (matches `update.sh`/`download-models.sh` pattern).

### Local models

For local models, Claude Code points at the ik_llama.cpp server on port 9080.
The script auto-detects WSL2 and uses the Windows host IP when needed (llama-server
runs as a Windows `.exe` on ProBook). On native Linux/macOS it uses `localhost`.
Ensure a model is loaded first: `./start.sh <machine> <mode>`.

### Bare mode

Both scripts use `--bare` mode by default to bypass claude.ai OAuth and let
`ANTHROPIC_API_KEY` take over. `--bare` disables hooks and CLAUDE.md auto-
discovery. If you prefer full features, run `claude /logout` first, then set
`CLAUDE_PROVIDERS_NO_BARE=1` to skip bare mode.

### Manual env vars (without the picker)

```bash
# Local (auto-detect WSL vs native)
export ANTHROPIC_BASE_URL=http://$(ip route show default | awk '{print $3; exit}'):9080  # WSL2
export ANTHROPIC_BASE_URL=http://localhost:9080                                            # native
export ANTHROPIC_API_KEY=dummy
export ANTHROPIC_CUSTOM_MODEL_OPTION=<gguf-stem>   # e.g. Qwopus3.6-35B-A3B-v1-Q6_K
export ANTHROPIC_DEFAULT_SONNET_MODEL=<gguf-stem>
export ANTHROPIC_DEFAULT_HAIKU_MODEL=<gguf-stem>
claude --bare --model <gguf-stem>                  # --bare required if signed into claude.ai

# OpenRouter
export ANTHROPIC_BASE_URL=https://openrouter.ai/api
export ANTHROPIC_API_KEY=$OPENROUTER_API_KEY
export ANTHROPIC_CUSTOM_MODEL_OPTION=anthropic/claude-sonnet-4
export ANTHROPIC_DEFAULT_SONNET_MODEL=anthropic/claude-sonnet-4
export ANTHROPIC_DEFAULT_HAIKU_MODEL=anthropic/claude-sonnet-4
claude --bare --model anthropic/claude-sonnet-4

# OpenCode Go (MiniMax/Qwen models only — Anthropic Messages API)
export ANTHROPIC_BASE_URL=https://opencode.ai/zen/go
export ANTHROPIC_API_KEY=$OPENCODE_GO_API_KEY
export ANTHROPIC_CUSTOM_MODEL_OPTION=qwen3.7-max
export ANTHROPIC_DEFAULT_SONNET_MODEL=qwen3.7-max
export ANTHROPIC_DEFAULT_HAIKU_MODEL=qwen3.7-plus
claude --bare --model qwen3.7-max

# NVIDIA NIM (Anthropic format may not work — route through OpenRouter if needed)
export ANTHROPIC_BASE_URL=https://integrate.api.nvidia.com
export ANTHROPIC_API_KEY=$NVIDIA_API_KEY
export ANTHROPIC_CUSTOM_MODEL_OPTION=nvidia/llama-4-maverick
export ANTHROPIC_DEFAULT_SONNET_MODEL=nvidia/llama-4-maverick
export ANTHROPIC_DEFAULT_HAIKU_MODEL=nvidia/llama-4-maverick
claude --bare --model nvidia/llama-4-maverick
```

Use the full GGUF stem as the model name for local, e.g. `Qwopus3.6-35B-A3B-v1-Q6_K`.

<Note>
  Don't include `/v1` in `ANTHROPIC_BASE_URL`. Claude Code appends `/v1/messages`
  to the value. Adding `/v1` doubles the path to `/v1/v1/messages` → 404.
</Note>

### Disable KV cache attribution header

The attribution header causes a ~90% slowdown with local servers. Add to `~/.claude/settings.json`:

```json
{
  "env": {
    "CLAUDE_CODE_ATTRIBUTION_HEADER": "0"
  }
}
```

## WSL2 memory config

Limit WSL2 memory to leave headroom for Windows (file: `C:\Users\<user>\.wslconfig`):

```ini
[wsl2]
memory=28GB
processors=6
swap=0
```

## Prompt cache warmup

The first message with a large system prompt is slow (cold cache). Send a short "hi" first to prime the cache — all subsequent messages will be fast.
