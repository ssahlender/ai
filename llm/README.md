# llm: the Windows-native local-LLM tooling

The **ProBook's** local inference stack: launcher, provider wiring, benchmarks and the quality
harness. Everything here is PowerShell and runs natively on Windows; no WSL, no `/mnt/c`.

The **Mac** does not use this directory: its daily driver is Ollama (`../ollama/README.md`), and
`../mlx/` holds the retired comparison. Model *files* are not stored here; engines and shared GGUFs
live under `$env:USERPROFILE\.local\share\llama.cpp` (matching the Linux/Mac convention; override
via `lib\common.ps1`'s `Get-LlmRoot -Override`) and are described in `MODELS.md`. Migrating from
the old `C:\data\llm` layout: `.\move-to-home.ps1` (`-WhatIf` first).

## What is installed right now (verified 2026-10-28)

| | |
|---|---|
| engine | mainline llama.cpp CPU build b11588 (updated 2026-10-13), `$env:USERPROFILE\.local\share\llama.cpp\llama.cpp-cpu` |
| model | `Qwen_Qwen3.6-35B-A3B-IQ4_NL.gguf` (bartowski, vanilla Qwen3.6, 19.33 GiB, MTP layers embedded) |
| mode | `qwen36_35b_ml`, **the only live mode**, runs `--spec-type draft-mtp`; `-ListOnly` shows it `[OK]` |

The i-quant engine (`ik_llama`) was removed on 2026-09-27 and the other seven modes were retired
with it. The HauhauCS Uncensored IQ4_NL that served until 2026-10-28 was replaced by the vanilla
family model above (same family as the other machines) and deleted; `MODELS.md` keeps its hash. `start-llm.ps1` lists them as a restorable comment block: fetch the file (`MODELS.md` has
repo + SHA-256) and paste the block back.

## Model and speculative decoding (A/B, 2026-10-28, mainline b11588)

Same engine and flags for every row (8/8 threads, q8_0 KV, ctx 8192, `--reasoning off`, greedy, 256
tokens, prompt cache off), decode tok/s, mean of 2 measured runs after a warm-up, run as an unattended
scheduled task. The HauhauCS control was run four times across the session and moved by up to ~25 % on
its own (edit 14-20 tok/s), so treat gaps under ~20 % as noise.

| model (all Qwen3.6-35B-A3B, IQ4_NL-class) | edit | prose | new code | prompt |
|---|---|---|---|---|
| HauhauCS Uncensored IQ4_NL, plain (previous live model, 4 runs) | 17.6 | 15.2 | 13.0 | ~60 |
| unsloth UD-IQ4_NL, plain | 9.3 | 9.3 | 9.4 | ~38 |
| unsloth MTP UD-IQ4_NL, plain | 9.4 | 9.2 | 9.2 | ~38 |
| unsloth MTP UD-IQ4_NL + `draft-mtp` n_max 1 / 3 | 12.1 / 14.4 | 11.7 / 10.1 | 12.1 / 12.7 | ~38 |
| **bartowski IQ4_NL, plain** | 12.4 | 14.1 | 14.1 | ~53 |
| **bartowski IQ4_NL + `draft-mtp` n_max 1** | 15.9 | 14.5 | 15.8 | ~49 |
| **bartowski IQ4_NL + `draft-mtp` n_max 3 (default; live)** | **19.0** | 12.8 | **17.3** | ~51 |

- **MTP layers cost nothing when unused**: the unsloth file with and without them decodes the same. The
  2026-10-13 "the MTP file is a third slower" finding was the unsloth *UD* quant, not MTP.
- **unsloth's UD quants are slow on this CPU** (~30 % decode, ~35 % prompt behind HauhauCS) although the
  file is smaller. Cause not established.
- **bartowski's standard IQ4_NL with `draft-mtp` matches the HauhauCS model on decode** (ahead on new code,
  level on edits, slightly behind on prose); prompt processing is ~15 % slower. Its GGUF embeds the MTP
  layers: the separate `mtp-...Q4_0.gguf` via `-md` measured identically, so it is not needed.
- Draft acceptance: 91/91 (n_max 1) and 135/138 (n_max 3) on the edit prompt.
- Quality, 6 scripted tasks x 3 samples at temperature 0.7 (graded by running the code): HauhauCS 15/18,
  bartowski 14/18, unsloth 14/18, unsloth MTP 12/18 -- no difference this sample size can call.

## Start the stack

Two ways to run it; pick one, never both at once (two supervisors would load the 19 GB model twice
and run out of RAM). All commands from `C:\data\git\ai-tools\llm`.

| | ports | who uses it |
|---|---|---|
| **A. manual** (default) | llama-server on 9080, `local-proxy.py` on 9081 | OpenCode talks to 9080, Claude Code to 9081 |
| **B. llama-swap** (optional) | `local-proxy.py` 9081 -> llama-swap 9082 -> llama-server | agents ask for a mode by name; llama-swap starts/stops the server |

**Thinking is off by default** (`--reasoning off`), the same as the i9's `start.sh` (`-rea off`).
Measured here: 12/12 in 6.0 s off vs 5/12 in 32.9 s on; on the i9 it was 8-9x slower with no quality
gain (`../ik-llama/README.md`, "Reasoning round"). `start-llm.ps1 ... -Thinking` turns it on for one run.

**Once per machine** (or after a fresh clone):

```powershell
.\update-llm.ps1                               # mainline llama.cpp engine
.\fetch-model.ps1 -Url https://huggingface.co/bartowski/Qwen_Qwen3.6-35B-A3B-GGUF/resolve/main/Qwen_Qwen3.6-35B-A3B-IQ4_NL.gguf `
  -FileName Qwen_Qwen3.6-35B-A3B-IQ4_NL.gguf -ExpectedBytes 20754978432     # then check the SHA-256 in MODELS.md
.\setup-agent-providers.ps1                    # writes ~/.config/opencode/opencode.json (-DryRun first)
```

**A. Manual: start, check, stop**

```powershell
.\start-llm.ps1 -ListOnly                      # every mode + resolved paths + OK/MISSING
.\start-llm.ps1 qwen36_35b_ml -Background      # 9080, detached; survives the calling session
(Invoke-RestMethod http://127.0.0.1:9080/health).status     # 'ok' once loaded, 503 while loading
opencode                                       # OpenCode uses 9080 directly
.\claude-local.ps1                             # Claude Code: starts the server if needed + local-proxy on 9081
Stop-Process -Name llama-server -Force         # there is no stop script
```

Loading 19 GB takes about a minute (66 s measured 2026-10-28); `/health` answers `503` until it is
ready. A server started from a PSRP session dies with that session; use `-Background`.

**B. llama-swap: start, check, stop** (verified 2026-10-28, llama-swap v268)

```powershell
.\update-llm.ps1 -Engine llama-swap            # once: installs llama-swap.exe (SHA-verified)
Stop-Process -Name llama-server -Force -ErrorAction SilentlyContinue   # no manual server alongside
.\llama-swap-setup.ps1 -WhatIf                 # print the generated config.yaml
.\llama-swap-setup.ps1                         # write it, start llama-swap on 9082, point local-proxy (9081) at it
.\setup-agent-providers.ps1 -BaseUrl http://127.0.0.1:9081/v1    # OpenCode through the proxy instead of 9080
Stop-Process -Name llama-swap,llama-server -Force                # stop; then rerun setup-agent-providers.ps1
                                                                  # without -BaseUrl to go back to manual
```

The first request after a start loads the model (79-90 s measured); later ones answer at normal
speed. `claude-local.ps1` belongs to the manual path: it starts its own server on 9080, so do not
run it while llama-swap is up.

## Talking to it: and the empty-answer trap

```powershell
$body = @{ model='…IQ4_NL'; messages=@(@{role='user';content='…'}); max_tokens=600; temperature=0 } | ConvertTo-Json -Depth 4
Invoke-RestMethod http://127.0.0.1:9080/v1/chat/completions -Method Post -Body $body -ContentType 'application/json'
```

**Measured behaviour (2026-09-27), because it is easy to mistake for a broken model:**

- With a small budget the answer is **empty**: `max_tokens = 32` returned `content = ""` with all
  32 tokens in `reasoning_content`. Give it headroom: at `max_tokens = 600` the same prompt
  returned `"ProBook local model works."` with `finish_reason = stop` (190 completion tokens,
  158 of them reasoning).
- Appending **`/no_think` does not suppress thinking** on this template (`max_tokens = 64` →
  empty content again). Increase the output budget, or serve with thinking off,
  which the launcher now does by default (`--reasoning off`; `-Thinking` turns it back on).
- The Mac behaves differently: there `think: false` (native API) and `reasoning_effort: "none"`
  (`/v1`) both work. See `../ollama/README.md`.

## Wiring agents to the local model

```powershell
.\setup-agent-providers.ps1 -DryRun    # show what it would write; nothing is launched
.\setup-agent-providers.ps1            # writes ~/.config/opencode/opencode.json
.\claude-local.ps1                     # Claude Code against the local server
```

`setup-agent-providers.ps1` reads the mode table out of `../ik-llama/models.json` (shared with
`start-llm.ps1` and the i9/Mac bash scripts, instead of each keeping its own list) and includes a mode only
when **both its GGUF and its engine's `llama-server.exe` exist**, so it cannot advertise something
that would fail at launch. It merges into the global OpenCode config (existing keys preserved),
names the provider for the engine that serves (`llamacpp`), and backs the old file up as
`opencode.json.bak`. `claude-local.ps1` defaults to `qwen36_35b_ml`; Claude Code needs
`CLAUDE_CODE_ATTRIBUTION_HEADER=0` in `~/.claude/settings.json` or local calls run ~90% slower
(`-FixSettings` writes it).

## Benchmarks, engines, models

| script | use |
|---|---|
| `bench\bench-matrix.ps1` | measures **every `.gguf` found in the models dir**, discovered at run time, so it cannot outlive its models |
| `bench\bench-ab.ps1`, `bench\bench-mtp.ps1` | **obsolete** (they required gemma-4-26B and the ik_llama engine). Kept as the method's record; they refuse and point at `bench-matrix.ps1` |
| `update-llm.ps1` | updates engines; default is `mainline` only. `-Engine ik_llama`/`llama-swap`/`all` bring the others in deliberately |
| `llama-swap-setup.ps1` | optional model routing/lifecycle via llama-swap, same stack as `ik-llama/llama-swap-setup.sh`; install the binary first with `update-llm.ps1 -Engine llama-swap`. verified end to end on the ProBook 2026-10-28 (llama-swap v268); run `-WhatIf` first |
| `fetch-model.ps1` | resumable, size-verified GGUF download. `tests\download-model.ps1` is a thin wrapper over it |
| `MODELS.md` | provenance: repo, exact bytes, SHA-256, and what is installed on which host |

## Tests

`llm\tests\` holds the quality harness (task set, deny policy, verdict rule, evidence publishing).
Its own self-tests are run by a scratch clone so they cannot disturb this working tree. Two of the
five still fail (deny-gate smuggling routes, derivability guard); the fixes are pending on the
`fix/harness-integrity` branch, and it is deliberately unmerged until its own gate passes.
