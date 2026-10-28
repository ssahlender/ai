# llm: local models on the ProBook, the i9 and the Mac

One model family everywhere (vanilla **Qwen3.6-35B-A3B**), one folder per machine, the same chain and
the same commands on each. The engines differ because the machines do.

## The chain (default on every machine)

```
agent (OpenCode, Pi, Claude Code, Docker Agent)
  -> local-proxy.py   :9081   keep-alives during long prefills, caps Claude Code's max_tokens
  -> llama-swap       :9082   web UI with stats, logs and a chat playground: http://127.0.0.1:9082/ui
  -> engine                   ProBook/i9: llama-server, started and stopped by llama-swap
                              Mac: Ollama (:11434), which loads models itself
```

Agents are configured for **9081** on all three machines. Everything listens on 127.0.0.1 only.

| machine | folder | engine | model (name in the llama-swap UI) | agent model id |
|---|---|---|---|---|
| ProBook (Windows 11, 32 GB, CPU) | [`probook/`](probook/) | mainline llama.cpp | Qwen3.6-35B-A3B IQ4_NL (bartowski) - MTP - 32K | `qwen36_35b_ml` |
| i9 (office, Debian 12, 64 GB, CPU) | [`i9/`](i9/) | ik_llama.cpp | Qwen3.6-35B-A3B MTP UD-Q6_K (unsloth) - suffix+MTP - 128K | `Qwen3.6-35B-A3B-MTP-UD-Q6_K` |
| MacBook Air M4 (24 GB, Metal) | [`mac/`](mac/) | Ollama | Qwen3.6-35B-A3B UD-Q2_K_XL (unsloth) - 32K - Ollama | `qwen36-35b-a3b` |

| what | ProBook (`llm\probook`) | i9 (`llm/i9`) | Mac (`llm/mac`) |
|---|---|---|---|
| install llama-swap (once) | `.\update-llm.ps1 -Engine llama-swap` (GitHub release, SHA-checked) | `brew` via `source ../../tools/_brew-i9.sh`, then `$BREW tap mostlygeek/llama-swap && $BREW install mostlygeek/llama-swap/llama-swap` | `../../tools/llama-swap-install.sh` (brew tap + install) |
| wire agents (once) | `.\setup-agents.ps1` | `../setup-agents.sh` | `../setup-agents.sh` |
| **start** | `.\llama-swap-setup.ps1` | `./llama-swap-setup.sh i9` | `./llama-swap-setup.sh` |
| Claude Code | `.\claude-local.ps1` (starts the chain if needed) | `../../tools/claude-providers.sh local` | `../../tools/claude-providers.sh local` |
| **stop** | `.\stop-llm.ps1` | `./stop.sh` | `./stop.sh` |

The first request after a start loads the model: about 1-1.5 min on the ProBook, seconds on the Mac.
The llama-swap UI shows it loading.

**Readable names** come from `name` in [`models.json`](models.json): llama-swap's UI and OpenCode show
them; the agent model id stays short. On the Mac, llama-swap lists the readable entry and the raw
`ollama/<name>`; both reach the same model.

**Agent setup is one codebase** for all three machines (`shared/setup_agents.py`): it detects the machine
(`--machine` overrides; an unknown machine is refused), writes only models that are really available, and
configures every installed agent (OpenCode, Pi, Docker Agent), removing references to models that are gone.

**Thinking is off by default** everywhere: `--reasoning off` (ProBook), `-rea off` (i9), and on the Mac
llama-swap adds `reasoning_effort: none` and `thinking: {type: disabled}` to every request. Measured much
slower with no quality gain ([`docs/i9.md`](docs/i9.md), "Reasoning round"). For one run with thinking:
ProBook `.\start-llm.ps1 qwen36_35b_ml -Thinking`, i9 `IK_LLAMA_EXTRA_ARGS='-rea on --reasoning-budget 2048'`,
Mac: call Ollama directly on 11434.

**Without llama-swap** (benchmarks, debugging): one bare server on 9080 with `start-llm.ps1 <mode>`
(ProBook) or `./start.sh i9 <mode>` (i9; also starts local-proxy on 9081), or `./start.sh` (Mac, Ollama in
the foreground). Point agents there with `setup-agents.ps1 -BaseUrl http://127.0.0.1:9080/v1`
(ProBook) or `../setup-agents.sh --base-url http://127.0.0.1:11434/v1` (Mac). Never run a bare server and llama-swap on
the same machine at once: the model would be loaded twice.

## Layout

| path | what |
|---|---|
| `models.json` | the model catalog for all three machines (one file, read by every script); a private lineup goes in `models.local.json` (gitignored, see `models.local.json.example`) |
| `MODELS.md` | provenance: repo, exact bytes, SHA-256, what is installed where, retired models |
| `shared/` | used by more than one machine: `local-proxy.py`, `ocg-proxy.py` (cloud proxy), `models.py` (catalog loader), `qwen3-template.j2`, `docker-compose.yml` (proxies only) |
| `probook/` | PowerShell: chain start/stop, bare launcher, updater, agent wiring, `claude-local.ps1`, `lib/common.ps1`, `bench/`, `tests/` (quality harness) |
| `i9/` | bash: chain start, bare launcher, stop, updater, downloads, agent wiring, model cleanup, benchmarks |
| `mac/` | bash: chain start, Ollama start/stop, agent wiring, a separate extraction instance for graphify |
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
.\claude-local.ps1 -FixSettings                # once: CLAUDE_CODE_ATTRIBUTION_HEADER=0, or local calls run ~90 % slower
```

A process started from a PSRP session dies with that session: start the chain from a real console or
a scheduled task.

i9 (`llm/i9`):

```bash
./update.sh i9                                 # ik_llama.cpp (Thireus prebuilt, AVX2)
./download-models.sh i9                        # the GGUFs listed in ../models.json
../setup-agents.sh                             # OpenCode, Pi, Docker Agent -> 9081 (--dry-run first)
./cleanup-models.sh i9                         # dry run: GGUFs not in the catalog
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
| `ik-llama/start.sh`, `update.sh`, `llama-swap-setup.sh` ... | `llm/i9/` (same names) |
| `ik-llama/setup-agents.sh`, `ollama/setup-agent.sh`, `llm/setup-agent-providers.ps1` | one codebase: `llm/shared/setup_agents.py`, run via `llm/setup-agents.sh` (i9, Mac) or `llm/probook/setup-agents.ps1` |
| `ik-llama/kill-proxy.sh`, `ik-llama/llama-swap-stop.sh` | `llm/i9/stop.sh` |
| `ik-llama/models.json`, `ik-llama/models.local.json` | `llm/models.json`, `llm/models.local.json` (move a private one by hand) |
| `ik-llama/local-proxy.py`, `ocg-proxy.py`, `models.py`, `qwen3-template.j2`, `docker-compose.yml` | `llm/shared/` |
| `ik-llama/claude-providers.sh`, `docker-agent-providers.sh`, `session-cleanup.sh` | `tools/` (`cagent-providers.sh` was a byte-identical copy: removed) |
| `llm/*.ps1`, `llm/lib`, `llm/bench`, `llm/tests` | `llm/probook/` |
| `ollama/*.sh` | `llm/mac/` |
| `ik-llama/README.md`, `AGENTS.md`, `ollama/README.md`, `mlx/README.md` | `llm/docs/` |
| `ik-llama/start.ps1`, `update.ps1`, `mlx/*.sh`, `llm/bench/bench-ab.ps1`, `bench-mtp.ps1` | removed (superseded; in git history) |
| the Mac's llama.cpp lineup in `models.json` (HauhauCS 27B/35B, Qwen3-Coder) | removed: the Mac runs Ollama only |

Provider ids (`ik-llama/<model>`, `ollama/<model>`, `llamacpp`) and model ids did not change. Since the same
day the llama-swap chain is the default: re-run the agent setup once on each machine (it moves agents to
9081) and start with `llama-swap-setup` instead of `start`. On the i9 that also rewrites llama-swap's
config, which held the old `start.sh` path.
