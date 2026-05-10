# ai-tools

Scripts for running local AI tools across multiple machines.

## Structure

| Path | Contents |
|---|---|
| `ik-llama/` | CPU-only LLM inference with ik_llama.cpp — models, server, OpenCode config (ProBook, i9) |
| `ollama/` | GPU-accelerated Ollama inference for Apple Silicon (MacBook Air M4) |
| `tools/` | Install/update scripts for AI coding tools (Claude Code, OpenCode, Codex, nvm, hf) |
| `docker/openwebui/` | Open WebUI docker-compose for Ollama |

---

## tools/

Install and update scripts for AI coding tools. All scripts are standalone — run them individually or use `update-all.sh` to update everything at once.

### Machine detection

Scripts detect the i9 work PC via proxy environment variables:

```bash
[[ -n "${http_proxy:-}${HTTP_PROXY:-}${https_proxy:-}${HTTPS_PROXY:-}" ]]
```

On i9, brew operations are printed as manual commands using the proxy-aware shell aliases (`brewupd` / `brewupg`) rather than run directly.

### update-all.sh

Runs all update scripts in order:

```bash
./update-all.sh
```

Order: `nvm-update.sh` → `claude-update.sh` → `opencode-update.sh` → `codex-update.sh` → `hf-update.sh`

Ollama update is commented out (run separately if needed).

---

### Claude Code

| Script | What it does |
|---|---|
| `claude-install.sh` | `curl -fsSL https://claude.ai/install.sh \| bash` |
| `claude-update.sh` | `claude update` |

---

### OpenCode

| Script | What it does |
|---|---|
| `opencode-install.sh` | `curl -fsSL https://opencode.ai/install \| bash` |
| `opencode-update.sh` | `opencode upgrade --method curl` |

---

### Codex (OpenAI CLI)

| Script | What it does |
|---|---|
| `codex-install.sh` | `brew install --cask codex` |
| `codex-update.sh` | `brew upgrade --cask codex` (prints manual command if no brew) |

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
| `hf-install.sh` | `brew install hf` (prints manual command on i9) |
| `hf-update.sh` | `brew upgrade hf` (prints manual command on i9) |

The binary is called `hf` (not `huggingface-cli`). Installed via brew formula `hf`.

---

### Ollama

| Script | What it does |
|---|---|
| `ollama-install.sh` | Checks GitHub for latest release, installs/updates via `ollama.com/install.sh` |
| `ollama-models-update.sh` | Pulls latest version of every installed model (`ollama list \| xargs ollama pull`) |

`ollama-install.sh` compares installed vs latest version and skips if already up to date.

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

See [`ik-llama/README.md`](ik-llama/README.md) for full details: hardware, models, flags, performance, and lessons learned.

---

## ollama/

GPU-accelerated local inference using Ollama on Apple Silicon (MacBook Air M4, 24 GB). Uses Metal GPU offload. Auto-discovers installed models for OpenCode config.

```bash
./tools/ollama-install.sh               # install Ollama binary
./ollama/download-models-mac.sh         # pull models (GGUF + Ollama tags)
./ollama/setup-opencode-mac.sh          # auto-generates provider config from ollama list
```

Models for 24 GB:
- `qwen36-27b-iq4nl` — Qwen3.6 27B dense IQ4_NL (~14 GB), best quality coding model
- `qwen3:14b` — Qwen3 14B dense (~9 GB), solid fallback
- `gemma3:12b` — Gemma3 12B dense (~8 GB), fast alternative
