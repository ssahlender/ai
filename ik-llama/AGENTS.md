# AI Agent Configuration

How to wire OpenCode and Claude Code to the local ik_llama.cpp server.

## OpenCode

Run the setup script for your machine — it merges the provider config and auth into your OpenCode installation:

```bash
# ProBook (WSL2)
./setup-opencode-probook.sh

# i9
./setup-opencode-i9.sh
```

The ProBook script auto-detects the Windows host IP from the WSL2 default gateway. The config files (`opencode-probook.json`, `opencode-i9.json`) use `WSL_HOST_IP` as a placeholder which the script substitutes at install time.

### Model shortnames

#### ProBook

| Shortname | Model |
|---|---|
| `ik-llama/qwen36u35b` | Qwen3.6-35B-A3B-Uncensored IQ4\_NL |
| `ik-llama/gemma4` | Gemma4-26B-A4B IQ4\_NL |
| `ik-llama/qwen3coder` | Qwen3-Coder-30B-A3B Q3\_K\_M |
| `ik-llama/glm4.7-flash` | GLM-4.7-Flash Q4\_K\_M |

#### i9

| Shortname | Model |
|---|---|
| `ik-llama/qwen36u27b` | Qwen3.6-27B-Uncensored Q5\_K\_P |
| `ik-llama/qwen36u35b` | Qwen3.6-35B-A3B-Uncensored Q4\_K\_P |
| `ik-llama/gemma4` | Gemma4-26B-A4B Q5\_K\_M |
| `ik-llama/supergemma4` | SuperGemma4-26B-Uncensored Q4\_K\_M |
| `ik-llama/glm4.7-flash` | GLM-4.7-Flash Q5\_K\_M |

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
