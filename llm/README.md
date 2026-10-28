# llm: local models on the ProBook, the i9 and the Mac

One model family everywhere (vanilla **Qwen3.6-35B-A3B**), one folder per machine, the same chain and
the same commands on each. The engines differ because the machines do.

## The chain (default on every machine)

```
agent (OpenCode, Pi, Claude Code, Docker Agent)
  -> local-proxy.py   :9081   keep-alives during long prefills, caps Claude Code's max_tokens
  -> llama-swap       :9082   web UI with stats, logs and a chat playground: http://127.0.0.1:9082/ui
  -> engine                   ProBook: mainline llama.cpp's llama-server, i9: ik_llama.cpp's llama-server,
                              both started and stopped by llama-swap
                              Mac: Ollama (:11434), which loads models itself
```

Agents are configured for **9081** on all three machines. Everything listens on 127.0.0.1 only.

| machine | folder | engine | model (one name: agents, llama-swap's model page and stats) |
|---|---|---|---|
| ProBook (Windows 11, 32 GB, CPU) | [`probook/`](probook/) | mainline llama.cpp | `Qwen3.6-35B-A3B-IQ4_NL-bartowski-MTP-32K` |
| i9 (office, Debian 12, 64 GB, CPU) | [`i9/`](i9/) | ik_llama.cpp | `Qwen3.6-35B-A3B-UD-Q6_K-unsloth-MTP-128K` (also `…-UD-Q5_K_XL-unsloth-MTP-256K`) |
| MacBook Air M4 (24 GB, Metal) | [`mac/`](mac/) | Ollama | `Qwen3.6-35B-A3B-UD-Q2_K_XL-unsloth-32K` |

The ProBook runs PowerShell from `llm\probook`; the i9 and the Mac share the same commands in `llm/`
(the machine is detected; `LLM_MACHINE=i9|mac` overrides it, an unknown machine is refused):

| what | ProBook (`llm\probook`) | i9 and Mac (`llm/`) |
|---|---|---|
| install llama-swap (once) | `.\update-llm.ps1 -Engine llama-swap` (GitHub release, SHA-checked) | `../tools/llama-swap-install.sh` (brew tap + install; on the i9 through the brewuser wrapper) |
| wire agents (once) | `.\setup-agents.ps1` | `./setup-agents.sh` |
| **start** | `.\llama-swap-setup.ps1` | `./llama-swap-setup.sh` (Mac: starts Ollama first) |
| Claude Code | `.\claude-local.ps1` (starts the chain if needed) | `../tools/claude-providers.sh local` |
| **stop** | `.\stop-llm.ps1` | `./stop.sh` |
| check | (in CI) | `./check.sh` |

The first request after a start loads the model: about 1-1.5 min on the ProBook, seconds on the Mac.
The llama-swap UI shows it loading.

**Each model has one name**, the `id` in [`models.json`](models.json), built the same way on every machine:
`<model>-<quant>-<publisher>[-MTP]-<context>K` (MTP = speculative decoding on). Agents, llama-swap's model
page, its stats and OpenCode all show that one name; `./check.sh` fails if a name does not match its own
entry (context, MTP). The GGUF file names stay as published, and the i9's `start.sh` modes are those file
names. On the Mac, llama-swap additionally lists Ollama's own model (`ollama/qwen36-35b-a3b`); both reach
the same model, agents use the readable one.

**Agent setup is one codebase** for all three machines (`shared/setup_agents.py`): it detects the machine
(`--machine` overrides; an unknown machine is refused), writes only models that are really available, and
configures every installed agent (OpenCode, Pi, Docker Agent), removing references to models that are gone.

**Thinking is off by default** everywhere: `--reasoning off` (ProBook), `-rea off` (i9), and on the Mac
llama-swap adds `reasoning_effort: none` and `thinking: {type: disabled}` to every request. Measured much
slower with no quality gain ([`docs/i9.md`](docs/i9.md), "Reasoning round"). For one run with thinking:
ProBook `.\start-llm.ps1 qwen36_35b_ml -Thinking`, i9 `IK_LLAMA_EXTRA_ARGS='-rea on --reasoning-budget 2048'`,
Mac: call Ollama directly on 11434.

**Without llama-swap** (benchmarks, debugging): one bare server on 9080 with `start-llm.ps1 <mode>`
(ProBook) or `i9/start.sh <mode>` (i9; also starts local-proxy on 9081), or `mac/start.sh` (Mac, Ollama in
the foreground). Point agents there with `setup-agents.ps1 -BaseUrl http://127.0.0.1:9080/v1`
(ProBook) or `./setup-agents.sh --base-url http://127.0.0.1:11434/v1` (Mac). Never run a bare server and llama-swap on
the same machine at once: the model would be loaded twice.

## Layout

| path | what |
|---|---|
| `models.json` | the model catalog for all three machines (one file, read by every script); a private lineup goes in `models.local.json` (gitignored, see `models.local.json.example`) |
| `MODELS.md` | provenance: repo, exact bytes, SHA-256, what is installed where, retired models |
| `shared/` | used by more than one machine: `local-proxy.py`, `ocg-proxy.py` (cloud proxy), `models.py` (catalog loader), `qwen3-template.j2`, `docker-compose.yml` (proxies only) |
| `probook/` | PowerShell: chain start/stop, bare launcher, updater, agent wiring, `claude-local.ps1`, `lib/common.ps1`, `bench/`, `tests/` (quality harness) |
| `llama-swap-setup.sh`, `stop.sh`, `setup-agents.sh`, `check.sh` | the shared commands for the i9 and the Mac (logic in `shared/`) |
| `i9/` | bash, i9 only: `start.sh` (a bare server; llama-swap runs it per model), updater, downloads, model cleanup and info, benchmarks, `move-to-home.sh` |
| `mac/` | bash, Mac only: `start.sh` (Ollama; `llama-swap-setup.sh` starts it when needed), the separate graphify instance (`start-graphify.sh`, `stop-graphify.sh`) |
| `docs/` | measurements and lessons: [`probook.md`](docs/probook.md), [`i9.md`](docs/i9.md), [`mac.md`](docs/mac.md), [`agents.md`](docs/agents.md) (proxies, Claude Code, Pi, Docker Agent, llama-swap), [`mlx-comparison.md`](docs/mlx-comparison.md) (retired), [`receipt-extraction-guide.md`](docs/receipt-extraction-guide.md) |

Engines and GGUFs live outside the repo, under `~/.local/share/llama.cpp/` (Windows:
`$env:USERPROFILE\.local\share\llama.cpp\`). Cloud-provider launchers (`claude-providers.sh`,
`docker-agent-providers.sh`) are in [`../tools/`](../tools/).

## First setup per machine

ProBook (`llm\probook`):

```powershell
.\update-llm.ps1                               # mainline llama.cpp
.\update-llm.ps1 -Engine llama-swap            # llama-swap
.\fetch-model.ps1 -Url https://huggingface.co/bartowski/Qwen_Qwen3.6-35B-A3B-GGUF/resolve/main/Qwen_Qwen3.6-35B-A3B-IQ4_NL.gguf `
  -FileName Qwen_Qwen3.6-35B-A3B-IQ4_NL.gguf -ExpectedBytes 20754978432     # then check the SHA-256 in ..\MODELS.md
.\setup-agents.ps1                            # OpenCode, Pi, Docker Agent -> 9081 (-DryRun first)
.\claude-local.ps1 -FixSettings                # first run: writes CLAUDE_CODE_ATTRIBUTION_HEADER=0 (else ~90 % slower),
                                               # then starts the chain if needed and opens Claude Code
```

A process started from a PSRP session dies with that session: start the chain from a real console or
a scheduled task.

i9 (`llm/i9`):

```bash
./update.sh                                    # ik_llama.cpp (Thireus prebuilt, AVX2)
./download-models.sh                           # the GGUFs listed in ../models.json
../setup-agents.sh                             # OpenCode, Pi, Docker Agent -> 9081 (--dry-run first)
./cleanup-models.sh                            # dry run: GGUFs not in the catalog
```

All i9 modes default to 8 threads and 24 batch threads (`IK_LLAMA_THREADS`, `IK_LLAMA_THREADS_BATCH`);
change them only for benchmarks.

Mac (`llm/mac`):

```bash
../../tools/ollama-install.sh && ../../tools/llama-swap-install.sh     # brew; updates: tools/update-all.sh
ollama pull hf.co/unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q2_K_XL               # 13 GB; then the 32K alias:
printf 'FROM hf.co/unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q2_K_XL\nPARAMETER num_ctx 32768\nPARAMETER temperature 0.7\n' | ollama create qwen36-35b-a3b -f -
../setup-agents.sh                             # OpenCode, Pi, Docker Agent -> 9081
```

Why Q2 and not a 4-bit quant (24 GB do not fit it), and the separate graphify instance
(`start-graphify.sh`, port 11438): [`docs/mac.md`](docs/mac.md).

## Moved here on 2026-10-28

`ik-llama/`, `ollama/`, `mlx/` and the old flat `llm/` were merged into this folder. After pulling:

| was | now |
|---|---|
| `ik-llama/start.sh`, `update.sh`, `download-models.sh` ... | `llm/i9/` (same names; the `i9` argument is now optional) |
| `ik-llama/setup-agents.sh`, `ollama/setup-agent.sh`, `llm/setup-agent-providers.ps1` | one codebase: `llm/shared/setup_agents.py`, run via `llm/setup-agents.sh` (i9, Mac) or `llm/probook/setup-agents.ps1` |
| `ik-llama/kill-proxy.sh`, `ik-llama/llama-swap-stop.sh`, `ollama/stop.sh` | `llm/stop.sh` (i9 and Mac) |
| `ik-llama/llama-swap-setup.sh`, later `llm/i9/` and `llm/mac/llama-swap-setup.sh` | `llm/llama-swap-setup.sh` (i9 and Mac; config from `llm/shared/llama_swap_config.py`) |
| `ik-llama/models.json`, `ik-llama/models.local.json` | `llm/models.json`, `llm/models.local.json` (move a private one by hand) |
| `ik-llama/local-proxy.py`, `ocg-proxy.py`, `models.py`, `qwen3-template.j2`, `docker-compose.yml` | `llm/shared/` |
| `ik-llama/claude-providers.sh`, `docker-agent-providers.sh`, `session-cleanup.sh` | `tools/` (`cagent-providers.sh` was a byte-identical copy: removed) |
| `llm/*.ps1`, `llm/lib`, `llm/bench`, `llm/tests` | `llm/probook/` |
| `ollama/start.sh`, `start-graphify.sh`, `stop-graphify.sh` | `llm/mac/` |
| `ik-llama/README.md`, `AGENTS.md`, `ollama/README.md`, `mlx/README.md` | `llm/docs/` |
| `ik-llama/start.ps1`, `update.ps1`, `mlx/*.sh`, `llm/bench/bench-ab.ps1`, `bench-mtp.ps1` | removed (superseded; in git history) |
| the Mac's llama.cpp lineup in `models.json` (HauhauCS 27B/35B, Qwen3-Coder) | removed: the Mac runs Ollama only |

Provider ids (`ik-llama`, `ollama`, `llamacpp`) did not change. Since the same day the llama-swap chain is the
default, and since 2026-10-29 every model has one readable name (table above) instead of the short ids
(`qwen36_35b_ml`, `qwen36-35b-a3b`, the i9's GGUF stems). After pulling, on each machine: run the agent
setup once (it points agents at 9081, writes the new names and removes references to the old ones), then
start with `llama-swap-setup` (it rewrites llama-swap's config, which held the old paths and names).
