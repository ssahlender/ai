# AI Agent Configuration

How to wire OpenCode and Claude Code to the local ik_llama.cpp server.

## OpenCode

Run the setup script for your machine — it parses the start script for model mappings and generates the provider config dynamically. Only models whose GGUF files exist on disk are included. OpenCode config is written only when `opencode` is installed.

```bash
# ProBook (WSL2)
./setup-agents-probook.sh

# i9
./setup-agents-i9.sh
```

The ProBook script auto-detects the Windows host IP from the WSL2 default gateway. The generated config uses `http://<host-ip>:8080/v1` (ProBook) or `http://localhost:9080/v1` (i9).

Model shortnames are derived from the `start-*.sh` case statements. Run the setup script to see available shortnames — they're printed after install. No static config file to maintain.

The old `setup-opencode-*.sh` names are compatibility wrappers around
`setup-agents-*.sh`.

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

Set these environment variables before launching `claude`:

```bash
# ProBook (WSL2) — adjust IP if needed
export ANTHROPIC_BASE_URL=http://$(ip route show default | awk '{print $3; exit}'):8080/v1
export ANTHROPIC_API_KEY=dummy
export ANTHROPIC_DEFAULT_SONNET_MODEL=<model-name>
export ANTHROPIC_DEFAULT_HAIKU_MODEL=<model-name>
claude
```

Use the full GGUF stem as the model name, e.g. `Qwen3.6-27B-Uncensored-HauhauCS-Aggressive-Q5_K_P`.

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
