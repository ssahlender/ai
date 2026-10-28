# llm: local models on the ProBook, the i9 and the Mac

One model family everywhere (vanilla **Qwen3.6-35B-A3B**), one folder per machine, the same verbs
on each: **start, stop, setup-agents, update**. The engines differ because the machines do.

| machine | folder | engine | model | agents talk to |
|---|---|---|---|---|
| ProBook (Windows 11, 32 GB, CPU) | [`probook/`](probook/) | mainline llama.cpp | bartowski IQ4_NL + MTP (`qwen36_35b_ml`) | OpenCode → 9080, Claude Code → 9081 |
| i9 (office, Debian 12, 64 GB, CPU) | [`i9/`](i9/) | ik_llama.cpp | unsloth MTP UD-Q6_K + suffix/MTP | everything → 9081 |
| MacBook Air M4 (24 GB, Metal) | [`mac/`](mac/) | Ollama | `qwen36-35b-a3b` (unsloth UD-Q2_K_XL) | everything → 11434 |

**Thinking is off by default** on the ProBook (`--reasoning off`) and the i9 (`-rea off`): measured much
slower with no quality gain ([`docs/i9.md`](docs/i9.md), "Reasoning round"). `start-llm.ps1 -Thinking`
turns it on for one ProBook run; on the i9 `IK_LLAMA_EXTRA_ARGS='-rea on --reasoning-budget 2048'`.
Ollama decides per request: send `"reasoning_effort": "none"` to turn it off ([`docs/mac.md`](docs/mac.md)).

## Layout

| path | what |
|---|---|
| `models.json` | the model catalog for the i9 and the ProBook (one file, read by every script); a private lineup goes in `models.local.json` (gitignored, see `models.local.json.example`) |
| `MODELS.md` | provenance: repo, exact bytes, SHA-256, what is installed where, retired models |
| `shared/` | used by more than one machine: `local-proxy.py` (agent port 9081, keep-alives, max_tokens cap), `ocg-proxy.py` (cloud proxy), `models.py` (catalog loader), `qwen3-template.j2`, `docker-compose.yml` (proxies only) |
| `probook/` | PowerShell: launcher, stop, updater, agent wiring, `claude-local.ps1`, llama-swap, `lib/common.ps1`, `bench/`, `tests/` (quality harness) |
| `i9/` | bash: launcher, stop, updater, downloads, agent wiring, llama-swap, model cleanup, benchmarks |
| `mac/` | bash: Ollama start/stop, agent wiring, a separate extraction instance for graphify |
| `docs/` | measurements and lessons: [`probook.md`](docs/probook.md), [`i9.md`](docs/i9.md), [`mac.md`](docs/mac.md), [`agents.md`](docs/agents.md) (proxies, Claude Code, Pi, Docker Agent, llama-swap), [`mlx-comparison.md`](docs/mlx-comparison.md) (retired), [`receipt-extraction-guide.md`](docs/receipt-extraction-guide.md) |

Engines and GGUFs live outside the repo, under `~/.local/share/llama.cpp/` (Windows:
`$env:USERPROFILE\.local\share\llama.cpp\`). Cloud-provider launchers (`claude-providers.sh`,
`docker-agent-providers.sh`) are in [`../tools/`](../tools/).

## ProBook (from `llm\probook`)

Once (or after a fresh clone):

```powershell
.\update-llm.ps1                               # mainline llama.cpp engine
.\fetch-model.ps1 -Url https://huggingface.co/bartowski/Qwen_Qwen3.6-35B-A3B-GGUF/resolve/main/Qwen_Qwen3.6-35B-A3B-IQ4_NL.gguf `
  -FileName Qwen_Qwen3.6-35B-A3B-IQ4_NL.gguf -ExpectedBytes 20754978432     # then check the SHA-256 in ..\MODELS.md
.\setup-agent-providers.ps1                    # writes ~/.config/opencode/opencode.json (-DryRun first)
```

Daily (manual: one model, llama-server on 9080):

```powershell
.\start-llm.ps1 -ListOnly                      # every mode + resolved paths + OK/MISSING
.\start-llm.ps1 qwen36_35b_ml -Background      # detached; ready in ~1 min
(Invoke-RestMethod http://127.0.0.1:9080/health).status     # 'ok' once loaded, 503 while loading
opencode                                       # uses 9080 directly
.\claude-local.ps1                             # Claude Code: starts the server if needed + local-proxy on 9081
.\stop-llm.ps1                                 # stops llama-server, llama-swap and local-proxy
```

A server started from a PSRP session dies with that session; use `-Background` from a real console,
or a scheduled task. `claude-local.ps1` needs `CLAUDE_CODE_ATTRIBUTION_HEADER=0` in
`~/.claude/settings.json` or local calls run ~90 % slower (`-FixSettings` writes it).

Optional, llama-swap (agents pick the model by name; verified 2026-10-28, v268):

```powershell
.\update-llm.ps1 -Engine llama-swap            # once
.\stop-llm.ps1                                 # never alongside a manual server: it would load the model twice
.\llama-swap-setup.ps1 -WhatIf                 # print the generated config.yaml
.\llama-swap-setup.ps1                         # llama-swap on 9082, local-proxy 9081 in front of it
.\setup-agent-providers.ps1 -BaseUrl http://127.0.0.1:9081/v1    # OpenCode through the proxy
```

Back to manual: `.\stop-llm.ps1`, then `.\setup-agent-providers.ps1` without `-BaseUrl`. The first
request after a llama-swap start loads the model (79-90 s).

## i9 (from `llm/i9`)

```bash
./update.sh i9                                 # ik_llama.cpp (Thireus prebuilt, AVX2)
./download-models.sh i9                        # the GGUFs listed in ../models.json
./setup-agents.sh i9                           # OpenCode + Pi + Docker Agent, provider ik-llama, port 9081
./start.sh i9 Qwen3.6-35B-A3B-MTP-UD-Q6_K      # llama-server 9080 + local-proxy 9081; no mode = numbered menu
./stop.sh                                      # stops llama-server, llama-swap, local-proxy (--all: cloud proxies too)
./cleanup-models.sh i9                         # dry run: GGUFs not in the catalog
```

Optional, llama-swap: `./llama-swap-setup.sh i9` (install first: `brew tap mostlygeek/llama-swap &&
brew install mostlygeek/llama-swap/llama-swap`, via `source ../../tools/_brew-i9.sh && $BREW ...`);
stop with `./stop.sh`. Agents keep using 9081 and the same model ids. Details: [`docs/agents.md`](docs/agents.md).

All i9 modes default to 8 threads and 24 batch threads (`IK_LLAMA_THREADS`, `IK_LLAMA_THREADS_BATCH`);
change them only for benchmarks.

## Mac (from `llm/mac`)

```bash
../../tools/ollama-install.sh                  # once: brew install ollama (updates: tools/update-all.sh)
ollama pull hf.co/unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q2_K_XL     # once, 13 GB; then create the 32K alias:
printf 'FROM hf.co/unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q2_K_XL\nPARAMETER num_ctx 32768\nPARAMETER temperature 0.7\n' | ollama create qwen36-35b-a3b -f -
./setup-agent.sh                               # OpenCode + Pi, model ollama/qwen36-35b-a3b
./start.sh                                     # ollama serve on 11434 (flash attention, q8_0 KV); foreground
./stop.sh
```

Why Q2 and not a 4-bit quant (the Mac's 24 GB do not fit it), and the separate graphify instance
(`start-graphify.sh`, port 11438): [`docs/mac.md`](docs/mac.md).

## Moved here on 2026-10-28

`ik-llama/`, `ollama/`, `mlx/` and the old flat `llm/` were merged into this folder. After pulling:

| was | now |
|---|---|
| `ik-llama/start.sh`, `setup-agents.sh`, `update.sh`, `llama-swap-setup.sh` ... | `llm/i9/` (same names) |
| `ik-llama/kill-proxy.sh`, `ik-llama/llama-swap-stop.sh` | `llm/i9/stop.sh` |
| `ik-llama/models.json`, `ik-llama/models.local.json` | `llm/models.json`, `llm/models.local.json` (move a private one by hand) |
| `ik-llama/local-proxy.py`, `ocg-proxy.py`, `models.py`, `qwen3-template.j2`, `docker-compose.yml` | `llm/shared/` |
| `ik-llama/claude-providers.sh`, `docker-agent-providers.sh`, `session-cleanup.sh` | `tools/` (`cagent-providers.sh` was a byte-identical copy: removed) |
| `llm/*.ps1`, `llm/lib`, `llm/bench`, `llm/tests` | `llm/probook/` |
| `ollama/*.sh` | `llm/mac/` |
| `ik-llama/README.md`, `AGENTS.md`, `ollama/README.md`, `mlx/README.md` | `llm/docs/` |
| `ik-llama/start.ps1`, `update.ps1`, `mlx/*.sh`, `llm/bench/bench-ab.ps1`, `bench-mtp.ps1` | removed (superseded; in git history) |
| the Mac's llama.cpp lineup in `models.json` (HauhauCS 27B/35B, Qwen3-Coder) | removed: the Mac runs Ollama only |

Provider ids (`ik-llama/<model>`, `ollama/<model>`, `llamacpp`), ports and model ids did not change,
so agent configs keep working. Re-run `./llama-swap-setup.sh i9` once if you use llama-swap: its
generated config holds the old `start.sh` path.
