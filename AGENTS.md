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

See [`ik-llama/`](ik-llama/) for unified setup:
- `download-models.sh macbook-air` — pulls GGUFs + mmproj from HF (same repos as i9)
- `setup-agents.sh macbook-air` — auto-generates OpenCode/Pi config
- `start.sh macbook-air` — Metal GPU via brew's llama.cpp, same flags + vision as i9

## tools/ scripts

No special agent config needed — scripts are self-contained bash. Run directly or via `update-all.sh`.

On the i9, scripts use the `_brew-i9.sh` helper which runs brew via `sudo -n -u brewuser` with the full absolute path. Other machines run brew directly.

## Large Generated Files

Do not write large generated artifacts such as draw.io XML, SVG, lock files, or
large JSON blobs as one inline tool-call string. Local OpenCode/Qwen tool calls
can fail with JSON parse errors when a large payload contains quoting,
newlines, or truncated strings.

For generated artifacts, create a small generator script or structured source
file, run it to write the artifact, and validate the result. If literal content
is unavoidable, write it in smaller chunks and verify the final file.
