# ai-tools

Scripts for running AI coding tools and local models across a few machines. This repository is public.

| Path | Contents |
|---|---|
| [`llm/`](llm/README.md) | **Local models**: one model catalog (`models.json`), shared commands for the i9 and the Mac, PowerShell for the ProBook (`probook/`), machine-only scripts in `i9/` and `mac/`, measurements in `llm/docs/` |
| [`tools/`](tools/README.md) | Install/update scripts for the AI CLIs (Claude Code, OpenCode, goose, Codex, Docker Agent, Antigravity, Pi, nvm, hf, RTK, context-mode, claude-mem, Graphify, Repomix, ccusage, Obsidian, Ollama, llama-swap), `update-all.sh`, and the cloud-provider pickers |
| [`AGENTS.md`](AGENTS.md) | Rules for AI agents working in this repo |

## Local models: which machine runs what

| machine | engine | model | start |
|---|---|---|---|
| ProBook (Windows) | mainline llama.cpp | `Qwen3.6-35B-A3B-IQ4_NL-bartowski-MTP-32K` | `llm\probook\llama-swap-setup.ps1`, then `opencode` or `llm\probook\claude-local.ps1` |
| i9 (Debian) | ik_llama.cpp | `Qwen3.6-35B-A3B-UD-Q6_K-unsloth-MTP-128K` | `llm/llama-swap-setup.sh` |
| MacBook Air M4 | Ollama | `Qwen3.6-35B-A3B-UD-Q2_K_XL-unsloth-32K` | `llm/llama-swap-setup.sh` |

Every machine runs the same chain: agents → `local-proxy.py` (9081) → llama-swap (9082, web UI with stats at
http://127.0.0.1:9082/ui) → engine. Stop with `llm\probook\stop-llm.ps1` / `llm/stop.sh`. Thinking is off
by default everywhere. Details, first setup and the bare-server path: [`llm/README.md`](llm/README.md).
The folders `ik-llama/`, `ollama/` and `mlx/` were merged into `llm/` on 2026-10-28, and the model names
changed on 2026-10-29: [`llm/README.md`](llm/README.md#moved-here-on-2026-10-28) maps old to new.

Open WebUI (a chat UI with logins) runs as an optional container next to the chain: `llm/README.md`, "Open WebUI".

Generated benchmark output (`bench-results/`) and Python caches are ignored by git.
