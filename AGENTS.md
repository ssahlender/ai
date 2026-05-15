# Agent Configuration

How to wire AI coding agents to the tools in this repo.

## Local LLM (OpenCode + Claude Code)

### x86 CPU (ProBook + i9)

See [`ik-llama/AGENTS.md`](ik-llama/AGENTS.md) for full setup:

- OpenCode provider config (setup scripts for ProBook and i9)
- Claude Code environment variables and model names
- Disabling the KV cache attribution header (causes ~90% slowdown with local servers)
- OpenCode local-speed mode for disabling MCP/plugins when local writes stall with low CPU
- WSL2 memory config
- Prompt cache warmup tip

### Apple Silicon (MacBook Air M4)

See [`ollama/`](ollama/) for Mac setup:

- Ollama + Metal GPU acceleration
- `download-models-mac.sh` — pulls models for 24 GB
- `setup-opencode-mac.sh` — auto-generates OpenCode provider config from `ollama list`
- No Claude Code env vars needed (use OpenCode with ollama provider)

## tools/ scripts

No special agent config needed — scripts are self-contained bash. Run directly or via `update-all.sh`.

On the i9, scripts use the `_brew-i9.sh` helper which runs brew via `sudo -n -u brewuser` with the full absolute path. Other machines run brew directly.
