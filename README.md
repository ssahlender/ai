# ai-tools

Scripts for running local AI tools across multiple machines.

## Structure

| Path | Contents |
|---|---|
| `ik-llama/` | CPU-only LLM inference with ik_llama.cpp — models, server, OpenCode config (ProBook, i9) |
| `ollama/` | GPU-accelerated Ollama inference for Apple Silicon (MacBook Air M4) |
| `tools/` | Install/update scripts for AI coding tools (Claude Code, OpenCode, Codex, Pi, nvm, hf, RTK, context-mode, claude-mem, Graphify) |
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

Order is defined by the `UPDATE_TOOLS` array in `update-all.sh`:
`nvm` → `claude` → `opencode` → `codex` → `hf` → `hermes` → `rtk` →
`context-mode` → `claude-mem` → `graphify` → `pi`. Ollama is updated
afterwards only if installed, then `brew upgrade` and `brew cleanup --prune=all`
run last. Each `*-update.sh` upgrades only if already installed and skips
otherwise — run `*-install.sh` for new tools.

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

### Pi Coding Agent

| Script | What it does |
|---|---|
| `pi-install.sh` | `$BREW install pi-coding-agent`, then installs Pi packages |
| `pi-update.sh` | `$BREW upgrade pi-coding-agent`, then refreshes Pi packages (skips if not installed) |
| `pi-init.sh` | Installs Pi-native packages: `context-mode`, `@sherif-fanous/pi-rtk`, and `@gaodes/pi-graphify` |

Pi itself is installed via Homebrew. Pi extensions/skills are installed with
Pi's own package manager:

```bash
pi install npm:context-mode
pi install npm:@sherif-fanous/pi-rtk
pi install npm:@gaodes/pi-graphify
```

On the i9/proxy environment, `pi-init.sh` runs these installs with
`NODE_OPTIONS=--use-openssl-ca`, `NODE_EXTRA_CA_CERTS`, and `NPM_CONFIG_CAFILE`
pointing at `/etc/ssl/certs/ca-certificates.crt` so npm/Node uses the system CA
store for corporate certificates. Override with `SYSTEM_CA_FILE=/path/to/ca.crt`
if the proxy CA bundle lives elsewhere.

`claude-mem` is intentionally not installed for Pi; there is no clear maintained
Pi package for it in this stack, and it would overlap with context/memory
extensions.

---

### nvm / Node

Skipped entirely on i9 — work provides its own Node stack.

| Script | What it does |
|---|---|
| `nvm-install.sh` | Installs nvm via brew, adds shell config block, installs LTS Node |
| `nvm-update.sh` | `brew upgrade nvm`, reinstalls LTS migrating global packages, `npm update -g`, removes old Node versions |

`nvm-update.sh` keeps the active/default Node version and removes older
installed versions after the update succeeds. Set `NVM_KEEP_OLD_VERSIONS=1` to
keep one extra newest version for rollback.

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
| `rtk-update.sh` | `$BREW upgrade rtk`, then refreshes Claude Code, Codex, OpenCode, and Pi integrations (skips if not installed) |
| `rtk-init.sh` | Runs `rtk init -g`, `rtk init -g --codex`, `rtk init -g --opencode`, and `rtk init -g --agent pi` |

RTK compresses command output before it reaches coding agents. After install/update, restart the affected agent sessions so hooks/plugins are loaded.

---

### Context Mode

| Script | What it does |
|---|---|
| `context-mode-install.sh` | `npm install -g context-mode`, then configures Claude Code, Codex, and OpenCode |
| `context-mode-update.sh` | `npm update -g context-mode`, then refreshes integrations (skips if not installed) |
| `context-mode-init.sh` | Re-applies integrations without reinstalling the npm package |
| `opencode-local-speed.sh` | Disables OpenCode-side helpers that can add latency around local model writes |

Default integrations:
- Codex: registers `context-mode` as a user MCP server.
- OpenCode: skipped by default for local-model speed. Set `CONTEXT_MODE_ENABLE_OPENCODE=1` to write the `context-mode` local MCP entry into `~/.config/opencode/opencode.json`.

Claude Code plugin installation is opt-in because it runs a background Bun plugin process. Enable it explicitly with:

```bash
CONTEXT_MODE_ENABLE_CLAUDE=1 ./context-mode-install.sh
CONTEXT_MODE_ENABLE_OPENCODE=1 ./context-mode-init.sh
```

For local ik_llama.cpp/OpenCode sessions, if "Preparing write" is slow while CPU usage
is low, disable OpenCode-side helpers and compare:

```bash
./opencode-local-speed.sh status
./opencode-local-speed.sh fast
```

`fast` disables `context-mode` in `opencode.json`, backs up and clears configured
plugin entries, and moves every auto-loaded file from
`~/.config/opencode/plugins/` to `~/.config/opencode/plugins.disabled/`.
Restore the MCP/plugin files with:

```bash
./opencode-local-speed.sh restore
```

Restart the affected agent sessions after install/update.

---

### Claude-Mem

| Script | What it does |
|---|---|
| `claude-mem-install.sh` | Installs/enables claude-mem integrations without auto-starting the worker; skips Codex/OpenCode reinstall unless forced |
| `claude-mem-update.sh` | Reports the available version and skips reinstall by default, because upstream update/install is interactive |
| `claude-mem-kill.sh` | Stops the claude-mem worker and kills common orphaned Bun/Chroma/MCP subprocesses |

Claude-Mem stores settings under `~/.claude-mem/settings.json` and may install worker dependencies. Its worker is a long-running Bun service on port `37700` by default, with Chroma MCP/Python subprocesses for semantic search and an internal Claude Haiku process for memory compression when the Claude provider is used.

Worker commands:

```bash
npx -y claude-mem@latest start
npx -y claude-mem@latest status
npx -y claude-mem@latest stop
./claude-mem-kill.sh
curl http://localhost:37700/api/health
```

Claude Code plugin installation is opt-in because it starts extra local services, including Bun, Chroma MCP, and an internal Claude process. Enable it explicitly with:

```bash
CLAUDE_MEM_ENABLE_CLAUDE=1 ./claude-mem-install.sh
```

OpenCode is installed non-interactively. Codex CLI gets the marketplace and hooks registered non-interactively, but the plugin itself may still need to be selected once from Codex's `/plugins` UI. Restart Codex and OpenCode after install/update so hooks/plugins are loaded.

Operational findings:
- Do not run claude-mem reinstall from `update-all.sh`: upstream `claude-mem update` currently maps to the same interactive install flow and can prompt with "Overwrite existing installation?".
- If Claude Code behaves oddly after testing the Claude plugin, disable it with `claude plugin disable claude-mem`, stop the worker with `npx -y claude-mem@latest stop`, and check for leftovers with `ps -eo pid,ppid,etime,cmd | rg -i 'bun|claude-mem|chroma-mcp|claude-haiku'`.
- To keep the plugin installed/enabled but clear a stuck worker, run `./claude-mem-kill.sh`.
- To clear the worker and disable the Claude Code plugin in one step, run `./claude-mem-kill.sh --disable-claude`.
- If Chroma MCP remains after stopping the worker, kill the leftover `chroma-mcp` process before restarting Claude.
- Keep Claude-Mem enabled first in OpenCode/Codex only; enable the Claude Code plugin only when explicitly testing whether the memory benefit outweighs the background-process cost.

To intentionally reinstall/repair claude-mem during updates:

```bash
CLAUDE_MEM_UPDATE_REINSTALL=1 ./claude-mem-update.sh
```

To force the upstream Codex/OpenCode installer again:

```bash
CLAUDE_MEM_FORCE_INSTALL=1 ./claude-mem-install.sh
```

---

### Graphify

| Script | What it does |
|---|---|
| `graphify-install.sh` | Installs the official PyPI package `graphifyy[openai,ollama,sql,pdf,office]` with `uv tool install`, falling back to `pipx`; then registers Claude Code, Codex, and OpenCode |
| `graphify-update.sh` | Upgrades Graphify with the same default extras when managed by `uv tool` or `pipx`, then refreshes integrations |
| `graphify-init.sh` | Re-registers Claude Code, Codex, and OpenCode integrations and enables Codex `multi_agent = true` |

Graphify's package name is `graphifyy` but the CLI is `graphify`. The default
extras are `openai,ollama,sql,pdf,office`, so the preferred installer is
`uv tool install 'graphifyy[openai,ollama,sql,pdf,office]'` on both Linux and
macOS. Override with `GRAPHIFY_EXTRAS=...`; use `GRAPHIFY_EXTRAS=` for the base
package only. On macOS, install `uv` with Homebrew (`brew install uv`) if it is
missing; the install script will also do this when Homebrew is available.
`pipx install 'graphifyy[...]'` is kept as a fallback for Linux systems that
already use pipx. On the i9/proxy environment, the scripts pass
`--system-certs` to `uv tool install` so corporate CA certificates are honored.

After install/update, restart Claude Code, Codex, and OpenCode sessions. Use it
inside a project with:

```bash
/graphify .
```

Codex uses `$graphify` instead of `/graphify`.

Graphify overlaps partly with context/memory tooling, but it is more of a
project knowledge-graph generator than a background memory worker. Keep OpenCode
local-speed testing in mind before enabling extra graph/query instructions in
large local-model sessions.

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
