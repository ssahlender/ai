# Agents, proxies, llama-swap, docker-compose

How OpenCode, Pi, Docker Agent and Claude Code talk to the local servers, the two proxies in `../shared/`, and the optional llama-swap and docker-compose layers. The short version per machine is in [`../README.md`](../README.md).

## OpenCode

Run the setup script for your machine; it reads `models.json` for model mappings and generates the provider config dynamically. Only models whose GGUF files exist on disk are included. Vision models automatically get `modalities` for image input. OpenCode config is written only when `opencode` is installed.

```bash
llm/setup-agents.sh                                # i9 (provider ik-llama) and Mac (provider ollama), machine detected
powershell -File llm\probook\setup-agents.ps1      # ProBook (provider llamacpp); same Python underneath
```

On the i9 the generated config uses `http://localhost:9081/v1` — `local-proxy.py`, not llama-server's own port
9080 directly. `start.sh` auto-starts the proxy alongside llama-server (same mechanism
`claude-providers.sh` already used for Claude Code), so OpenCode/Pi also get SSE keep-alives during
cold-prefill or queued-request gaps instead of a bare "Timed out waiting for response headers" from
the client. Override the agent-facing port with `IK_LLAMA_AGENT_PORT`; llama-server's own port is
still `IK_LLAMA_PORT` (default 9080).

**Caveat:** this only helps if local-proxy.py is actually running. It auto-starts the next time you
(re)launch the model via `start.sh`; if llama-server was already running from before this existed (or
started some other way), restart it via `start.sh` once, or start the proxy by hand:
`LOCAL_PROXY_UPSTREAM=http://127.0.0.1:9080 LOCAL_PROXY_PORT=9081 python3 llm/shared/local-proxy.py &`. (On the ProBook, OpenCode talks to 9080 directly; see `../README.md`.)

Model ids are the GGUF file names without `.gguf`, derived from `models.json` (the ProBook uses the short mode names of `llm/probook/start-llm.ps1`, e.g. `qwen36_35b_ml`). Run the agent setup to see them; they're printed after install. Each run also removes stale `ik-llama/<id>` references (OpenCode `model`/`small_model`/agent models, Pi `defaultModel`, Docker Agent `default_model`); use `--dry-run` to preview. No static config file to maintain.

## Pi

The agent setup writes `~/.pi/agent/models.json` on every machine where Pi is installed. The Pi
provider key is the machine's provider (`ik-llama`, `ollama`, `llamacpp`); model ids are the same as
OpenCode's (for example `Qwen3.6-35B-A3B-MTP-UD-Q6_K` on the i9).

### Large tool writes

With local ik_llama.cpp/OpenCode, avoid generating large files directly inside
one write/edit tool call. This is especially important for draw.io XML, SVG, and
large JSON, where malformed escaping or truncation can produce errors like
`JSON Parse error: unterminated string`.

Instead, create a compact generator script or structured source file, run it to
write the large artifact, then validate the output. For draw.io, generate the
`.drawio` XML from data in a script rather than inlining the full XML payload in
the tool call.

## Docker Agent (docker-agent / cagent)

Use `docker-agent-providers.sh` to pick local or remote models interactively, mirroring `claude-providers.sh`:

```bash
# Interactive picker (Local + OpenCode Go + OpenRouter)
./docker-agent-providers.sh

# Direct launch (skip picker)
./docker-agent-providers.sh local
./docker-agent-providers.sh opencode-go qwen3.7-max
./docker-agent-providers.sh openrouter meta-llama/llama-4-maverick
```

The setup script (`llm/setup-agents.sh`) configures the `ik-llama` provider in `~/.config/cagent/config.yaml`
pointing to `http://localhost:9081/v1` — through `local-proxy.py`, same as OpenCode and Pi above (merging
with any existing options).

- **Local models**: Run directly with `--model ik-llama/<gguf-stem>`, for example:
  ```bash
  docker-agent run --model ik-llama/Qwen3.6-35B-A3B-MTP-UD-Q6_K coder "prompt"
  ```
- **OpenCode Go & Cloud models**: `setup-agents` syncs credentials (`OPENCODE_API_KEY`,
  `OPENROUTER_API_KEY`, `NVIDIA_API_KEY`) into `~/.config/cagent/.env` (mode 0600)
  from `~/.secrets` (`OPENCODE_API_KEY` or `OPENCODE_GO_API_KEY`).
  Run OpenCode Go models directly via the built-in provider:
  ```bash
  docker-agent run --model opencode-go/qwen3.7-max coder "prompt"
  ```
- Check credentials and configuration at any time:
  ```bash
  docker-agent doctor
  ```

## Claude Code

Use `claude-providers.sh` to pick local or remote models interactively. Type
numbers to select; no typing model names:

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

### Local models and the max_tokens proxy

For local models, Claude Code connects through `local-proxy.py` on port **9081**
(not directly to llama-server on 9080). The proxy is auto-started by `claude-providers.sh`
when you pick `local`. It intercepts every `/v1/messages` request and caps
`max_tokens` to `ctx/8` before forwarding to llama-server.

**Why the proxy is needed**: Claude CLI always sends `max_tokens=32000`. When
`input_tokens + 32000 > n_ctx`, llama-server rejects the request with
`"the request exceeds the available context size"`. The proxy caps the value so
87.5% of context stays available for input.

The proxy logs to `/tmp/local-proxy.log`. Stop it with `llm/i9/stop.sh` (`--all` also stops the cloud proxies).

The script uses `localhost` by default (configurable via `IK_LLAMA_HOST` and `IK_LLAMA_PORT`).
Ensure a model is loaded first: `llm/i9/start.sh i9 <mode>`.

### Bare mode

Both `claude-providers.sh` and `claude-local.ps1` use `--bare` mode by default to bypass claude.ai OAuth and let
`ANTHROPIC_API_KEY` take over. `--bare` disables hooks and CLAUDE.md auto-
discovery. If you prefer full features, run `claude /logout` first, then set
`CLAUDE_PROVIDERS_NO_BARE=1` to skip bare mode.

### Manual env vars (without the picker)

```bash
# Local — point at the proxy on 9081, NOT directly at llama-server on 9080.
# Start local-proxy.py first, or just use claude-providers.sh local (it does it).
export ANTHROPIC_BASE_URL=http://localhost:9081
export ANTHROPIC_API_KEY=dummy
export ANTHROPIC_CUSTOM_MODEL_OPTION=<gguf-stem>   # e.g. Qwen3.6-35B-A3B-MTP-UD-Q6_K
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

Use the full GGUF stem as the model name for local, e.g. `Qwen3.6-35B-A3B-MTP-UD-Q6_K`.

> [!NOTE]
> Don't include `/v1` in `ANTHROPIC_BASE_URL`. Claude Code appends `/v1/messages`
> to the value. Adding `/v1` doubles the path to `/v1/v1/messages` → 404.

### Disable KV cache attribution header

Claude Code puts an attribution line (`x-anthropic-billing-header: cc_version=...`) at the very start of the system prompt, and its suffix is a hash of the user's message. It changes with the message, so the local server's prompt prefix never matches and every turn pays a full cold prefill (about 120 s instead of 1 s at 13K tokens, measured). `claude-providers.sh` now sets `CLAUDE_CODE_ATTRIBUTION_HEADER=0` itself. For manual launches set it in the environment (`CLAUDE_CODE_ATTRIBUTION_HEADER=0 claude ...`) or add it to `~/.claude/settings.json`:

```json
{
  "env": {
    "CLAUDE_CODE_ATTRIBUTION_HEADER": "0"
  }
}
```

### Context window and harness-side compaction

Claude Code inspects `context_window` in the Anthropic `/v1/models` response. Because local servers return context info in extensions or fall back to `n_ctx_train` (e.g. 262K for Qwen3-Coder-Next), Claude Code does not trigger automatic context compaction until the session grows huge.

- **Keep operating depth at 16K–32K**: Ingesting uncached context on CPU at ~100 t/s scales linearly with length (>8 minutes for 50K; >20 minutes for 128K).
- **Run `/compact` proactively**: Execute `/compact` manually before sessions exceed 32K tokens to maintain snappy turnarounds and maximize prompt cache hits.
- **Hybrid attention models**: On models using hybrid linear attention (such as Qwen3-Coder-Next with Gated DeltaNet), recurrent state cannot be shifted by server-side context shift, making harness-side compaction mandatory.

## Prompt cache warmup

The first message with a large system prompt requires a cold prefill. A short "hi" can warm the shared prefix; subsequent requests benefit when that prefix stays unchanged and the server retains the cache.

## llama-swap (the default chain on every machine since 2026-10-28)

The short version, including the Mac (llama-swap in front of Ollama as a peer), is in [`../README.md`](../README.md). The details below are the i9 and ProBook implementation.

By default `llm/i9/start.sh i9 <mode>` runs one model at a time on port 9080, picked manually. For
switching models by name from the harness instead, [llama-swap](https://github.com/mostlygeek/llama-swap)
can sit between the proxy and llama-server:

```
harness -> local-proxy.py (9081, keep-alive) -> llama-swap (9082, routing/lifecycle) -> llama-server
```

Install (brew tap; on i9 this works through the corporate proxy): `brew tap mostlygeek/llama-swap && brew install mostlygeek/llama-swap/llama-swap`
(use `source tools/_brew-i9.sh && $BREW ...` on i9). ProBook: `llm\probook\update-llm.ps1 -Engine llama-swap`.

```bash
llm/i9/llama-swap-setup.sh i9       # stop everything again: llm/i9/stop.sh
```

This generates `~/.config/llama-swap/config.yaml` from `models.json` (one entry per
GGUF present on disk for that machine), each model's `cmd` driving `start.sh i9 <mode>`
itself via `IK_LLAMA_PRINT_CMD=1` + `eval` so llama-swap reuses the exact flags `start.sh` would
use (SAMPLE/YARN/MMPROJ/SPEC/CTX_CKPT conditionals included) instead of a second copy of that logic
drifting out of sync. It then starts llama-swap on 9082 and repoints `local-proxy.py`'s upstream
at it, leaving the agent-facing port (9081) and model ids (GGUF stems) unchanged —
the agent config does not need to change either way. ProBook has its own equivalent,
`llm\probook\llama-swap-setup.ps1` (install the binary first: `update-llm.ps1 -Engine llama-swap`) --
same stack, generated from the same `models.json`, reusing `start-llm.ps1`'s own flag-building
function (`Get-ServerInvocation` in `llm\probook\lib\common.ps1`) instead of a second copy. Verified
end to end on the ProBook 2026-10-28 (llama-swap v268); run `-WhatIf` first. On the ProBook,
OpenCode defaults to the manual port 9080, so point it at the proxy with
`setup-agents.ps1` (default URL is the chain on 9081; see `../README.md`).

**Do not run both at once against the same model.** `start.sh` run manually
(port 9080) and llama-swap are two independent supervisors; llama-swap doesn't know about a
manually-started `llama-server`, so requesting that same model through llama-swap would load a
second copy of it alongside the manual one — an OOM risk on a RAM-constrained box, not just
wasted memory. Stop the manual instance first (or don't point any harness at 9081 while it's
serving a live session) before routing requests through llama-swap.

To go back to manual mode: `llm/i9/stop.sh`, then `llm/i9/start.sh i9 <mode>` as usual (it restarts
`local-proxy.py` pointed at 9080).

## Optional: docker-compose for the tooling (not the engine)

`docker-compose.yml` containerizes `local-proxy.py` and `ocg-proxy.py` -- the same two
scripts documented natively above, same env vars, same ports, nothing in the agent setup
or any agent config needs to change either way. It's an alternative way to run them, not an
additional one: don't run a proxy both natively and via compose at once.

```bash
docker compose up -d                  # local-proxy only, no secrets required
docker compose --profile ocg up -d    # + ocg-proxy (needs OCG_PROXY_API_KEY)
```

The engine itself (llama-server/llama-swap) is deliberately **not** in this file. Docker
Desktop has no Metal GPU passthrough on Mac (that's the whole reason the Mac's daily driver
is native Ollama), and Docker Desktop's performance backend on Windows is WSL2 -- which was
already tried and rejected for the ProBook ("all tooling is native Windows," operator
decision). Both proxies have no such dependency: `local-proxy.py` just relays HTTP/SSE to
whatever `LOCAL_PROXY_UPSTREAM` points at (`host.docker.internal:9080` from inside the
container, reaching the native engine on the host), and `ocg-proxy.py` talks straight to the
internet. The compose file also has a commented-out example service for adding your own MCP
server containers (most ship one already) alongside the proxies.
