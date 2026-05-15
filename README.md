# ai-tools

Scripts for running local AI tools across multiple machines.

## Structure

| Path | Contents |
|---|---|
| `ik-llama/` | CPU-only LLM inference with ik_llama.cpp — models, server, OpenCode config (ProBook, i9) |
| `ollama/` | GPU-accelerated Ollama inference for Apple Silicon (MacBook Air M4) |
| `tools/` | Install/update scripts for AI coding tools (Claude Code, OpenCode, Codex, nvm, hf, RTK, context-mode, claude-mem) |
| `docker/openwebui/` | Open WebUI docker-compose for Ollama |

---

## tools/

Install and update scripts for AI coding tools. Core CLIs are installed via Homebrew where available; Node-based agent integrations use npm/npx. Run scripts individually or use `update-all.sh` to update everything at once.

### Machine detection

Scripts detect the i9 work PC via proxy environment variables (`tools/_brew-i9.sh`). On i9, brew runs via `sudo -n -u brewuser`. On all other machines, brew runs directly. To enable on i9: add the brew binary to sudoers with the `NOPASSWD` flag.

### update-all.sh

```bash
./update-all.sh
```

Order: `nvm-update.sh` → `claude-update.sh` → `opencode-update.sh` → `codex-update.sh` → `hf-update.sh` → `hermes-update.sh` → `rtk-update.sh` → `context-mode-update.sh` → `claude-mem-update.sh` → `ollama-update.sh` → `ollama-models-update.sh` (ollama only runs if installed) → `brew upgrade` (all packages) → `brew cleanup --prune=all`. Each `*-update.sh` upgrades only if already installed and skips otherwise — run `*-install.sh` for new tools.

---

### Claude Code

| Script | What it does |
|---|---|
| `claude-install.sh` | `$BREW install --cask claude-code` |
| `claude-update.sh` | `$BREW upgrade --cask claude-code` (skips if not installed) |

---

### OpenCode

| Script | What it does |
|---|---|
| `opencode-install.sh` | `$BREW install opencode` |
| `opencode-update.sh` | `$BREW upgrade opencode` (skips if not installed) |

---

### Codex (OpenAI CLI)

| Script | What it does |
|---|---|
| `codex-install.sh` | `$BREW install --cask codex` |
| `codex-update.sh` | `$BREW upgrade --cask codex` (skips if not installed) |

---

### nvm / Node

Skipped entirely on i9 — work provides its own Node stack.

| Script | What it does |
|---|---|
| `nvm-install.sh` | Installs nvm via brew, adds shell config block, installs LTS Node |
| `nvm-update.sh` | `brew upgrade nvm`, reinstalls LTS migrating global packages, `npm update -g` |

Shell config detection: zsh → `~/.zshrc`, bash+macOS → `~/.bash_profile`, bash+Linux → `~/.bashrc`.

NVM block appended (idempotent):
```bash
export NVM_DIR="$HOME/.nvm"
[ -s "$(brew --prefix)/opt/nvm/nvm.sh" ] && . "$(brew --prefix)/opt/nvm/nvm.sh"
```

---

### Hugging Face CLI (hf)

| Script | What it does |
|---|---|
| `hf-install.sh` | `$BREW install hf` |
| `hf-update.sh` | `$BREW upgrade hf` (skips if not installed) |

The binary is called `hf` (not `huggingface-cli`). Installed via brew formula `hf`.

---

### Hermes Agent (Nous Research)

| Script | What it does |
|---|---|
| `hermes-install.sh` | `$BREW install hermes-agent` |
| `hermes-update.sh` | `$BREW upgrade hermes-agent` (skips if not installed) |

---

### RTK (Rust Token Killer)

| Script | What it does |
|---|---|
| `rtk-install.sh` | `$BREW install rtk`, then initializes Claude Code, Codex, and OpenCode integrations |
| `rtk-update.sh` | `$BREW upgrade rtk`, then refreshes Claude Code, Codex, and OpenCode integrations (skips if not installed) |
| `rtk-init.sh` | Runs `rtk init -g`, `rtk init -g --codex`, and `rtk init -g --opencode` |

RTK compresses command output before it reaches coding agents. After install/update, restart the affected agent sessions so hooks/plugins are loaded.

---

### Context Mode

| Script | What it does |
|---|---|
| `context-mode-install.sh` | `npm install -g context-mode`, then configures Claude Code, Codex, and OpenCode |
| `context-mode-update.sh` | `npm update -g context-mode`, then refreshes integrations (skips if not installed) |
| `context-mode-init.sh` | Re-applies integrations without reinstalling the npm package |

Integrations:
- Claude Code: adds marketplace `mksglu/context-mode`, then installs `context-mode@context-mode`.
- Codex: registers `context-mode` as a user MCP server.
- OpenCode: writes the `context-mode` local MCP entry into `~/.config/opencode/opencode.json`.

Restart the affected agent sessions after install/update.

---

### Claude-Mem

| Script | What it does |
|---|---|
| `claude-mem-install.sh` | Runs the official `npx -y claude-mem@latest install` flow for Claude Code, Codex CLI, and OpenCode |
| `claude-mem-update.sh` | Re-runs the installer when claude-mem appears to be installed, otherwise skips |

Claude-Mem stores settings under `~/.claude-mem/settings.json` and may install its worker dependencies. Start the worker with `npx -y claude-mem@latest start` and check it with `npx -y claude-mem@latest status` or `curl http://localhost:37700/api/health`.

Claude Code and OpenCode are installed non-interactively. Codex CLI gets the marketplace and hooks registered non-interactively, but the plugin itself may still need to be selected once from Codex's `/plugins` UI. Restart Claude Code, Codex, and OpenCode after install/update so hooks/plugins are loaded.

---

### Ollama

| Script | What it does |
|---|---|
| `ollama-install.sh` | `$BREW install ollama` (skipped on i9 — CPU too slow) |
| `ollama-update.sh` | `$BREW upgrade ollama` (skipped on i9) |
| `ollama-models-update.sh` | Pulls latest version of every installed model (`ollama list \| xargs ollama pull`) |

---

## docker/openwebui/

Open WebUI connected to a local Ollama instance.

```bash
cd docker/openwebui
docker compose up -d
```

- Listens on port **3000**
- Connects to Ollama at `host.docker.internal:11434`
- `OFFLINE_MODE=True` — no external calls
- Proxy env vars explicitly cleared so container bypasses any system proxy
- Data volume: `~/docker/openwebui/data`

---

## ik-llama/

CPU-only local LLM inference using [ik_llama.cpp](https://github.com/Thireus/ik_llama.cpp) on two machines (HP ProBook + i9-13900). Models: Qwen3.6, Gemma4, GLM-4.7-Flash.

See [`ik-llama/README.md`](ik-llama/README.md) for full details: hardware, models, flags, benchmark scripts, performance, and lessons learned.

Generated benchmark output goes into `bench-results/` and is intentionally ignored by git. Python bytecode caches such as `__pycache__/` and `*.pyc` are also ignored.

---

## ollama/

GPU-accelerated local inference using Ollama on Apple Silicon (MacBook Air M4, 24 GB). Uses Metal GPU offload. Auto-discovers installed models for OpenCode config.
See [`ollama/README.md`](ollama/README.md) for speed guidance and Ollama vs direct llama.cpp notes.

```bash
./tools/ollama-install.sh               # install Ollama binary
./ollama/download-models-mac.sh         # pull models (GGUF + Ollama tags)
./ollama/setup-opencode-mac.sh          # auto-generates provider config from ollama list
```

Models for 24 GB:
- `qwen36-27b-iq4nl` — Qwen3.6 27B dense IQ4_NL (~14 GB), best quality coding model
- `qwen3:14b` — Qwen3 14B dense (~9 GB), solid fallback
- `gemma3:12b` — Gemma3 12B dense (~8 GB), fast alternative
