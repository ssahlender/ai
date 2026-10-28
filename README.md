# ai-tools

Scripts for running AI coding tools and local models across a few machines. This repository is public.

| Path | Contents |
|---|---|
| [`llm/`](llm/README.md) | **Local models**: one folder per machine (`probook/`, `i9/`, `mac/`), shared proxies and catalog, measurements in `llm/docs/` |
| [`tools/`](tools/README.md) | Install/update scripts for the AI CLIs (Claude Code, OpenCode, Codex, Docker Agent, Antigravity, Pi, nvm, hf, RTK, context-mode, claude-mem, Graphify, Repomix, ccusage, Obsidian, Ollama, llama-swap), `update-all.sh`, and the cloud-provider pickers |
| `docker/openwebui/` | Open WebUI docker-compose for Ollama (below) |
| [`AGENTS.md`](AGENTS.md) | Rules for AI agents working in this repo |

## Local models: which machine runs what

| machine | engine + model | start | details |
|---|---|---|---|
| ProBook (Windows) | mainline llama.cpp, Qwen3.6-35B-A3B IQ4_NL + MTP | `llm\probook\start-llm.ps1 qwen36_35b_ml -Background`, then `opencode` or `llm\probook\claude-local.ps1` | [`llm/README.md`](llm/README.md#probook-from-llmprobook) |
| i9 (Debian) | ik_llama.cpp, Qwen3.6-35B-A3B MTP UD-Q6_K | `llm/i9/start.sh i9 Qwen3.6-35B-A3B-MTP-UD-Q6_K` | [`llm/README.md`](llm/README.md#i9-from-llmi9) |
| MacBook Air M4 | Ollama, `qwen36-35b-a3b` (UD-Q2_K_XL) | `llm/mac/start.sh` | [`llm/README.md`](llm/README.md#mac-from-llmmac) |

Stop with `stop-llm.ps1` / `stop.sh` in the same folder. Thinking is off by default on the ProBook and the
i9; on the Mac it is set per request. The folders `ik-llama/`, `ollama/` and `mlx/` were merged into `llm/`
on 2026-10-28: [`llm/README.md`](llm/README.md#moved-here-on-2026-10-28) maps old paths to new.

Generated benchmark output (`bench-results/`) and Python caches are ignored by git.

## docker/openwebui

Open WebUI connected to a local Ollama instance.

```bash
cd docker/openwebui
docker compose up -d
```

- Listens on port **3000**
- Connects to Ollama at `host.docker.internal:11434`
- `OFFLINE_MODE=True`: no external calls
- Proxy env vars explicitly cleared so container bypasses any system proxy
- Data volume: `~/docker/openwebui/data`
