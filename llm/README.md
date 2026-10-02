# llm: the Windows-native local-LLM tooling

The **ProBook's** local inference stack: launcher, provider wiring, benchmarks and the quality
harness. Everything here is PowerShell and runs natively on Windows; no WSL, no `/mnt/c`.

The **Mac** does not use this directory: its daily driver is Ollama (`../ollama/README.md`), and
`../mlx/` holds the retired comparison. Model *files* are not stored here; engines and shared GGUFs
live under `C:\data\llm` and are described in `MODELS.md`.

## What is installed right now (verified 2026-09-27)

| | |
|---|---|
| engine | mainline llama.cpp CPU, `C:\data\llm\llama.cpp-cpu` |
| model | `Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-IQ4_NL.gguf` (18.42 GiB) |
| mode | `qwen36u35b_ml`, **the only live mode**; `-ListOnly` shows it `[OK]` |

The i-quant engine (`ik_llama`) was removed on 2026-09-27 and the other seven modes were retired
with it. `start-llm.ps1` lists them as a restorable comment block: fetch the file (`MODELS.md` has
repo + SHA-256) and paste the block back.

## Start, check, stop

```powershell
.\start-llm.ps1 -ListOnly                      # every mode + resolved paths + OK/MISSING
.\start-llm.ps1 qwen36u35b_ml -Background      # detached; survives the calling session
(Invoke-RestMethod http://127.0.0.1:9080/health).status     # 'ok' once loaded, 503 while loading
Stop-Process -Name llama-server -Force         # there is no stop script
```

Loading 18 GB takes roughly half a minute; `/health` answers `503` until it is ready. A server
started from a PSRP session dies with that session; use `-Background`.

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
  empty content again). Increase the output budget, or use the launcher's
  `-NoThinking` switch, which passes `--reasoning off` to llama-server.
- The Mac behaves differently: there `think: false` (native API) and `reasoning_effort: "none"`
  (`/v1`) both work. See `../ollama/README.md`.

## Wiring agents to the local model

```powershell
.\setup-agent-providers.ps1 -DryRun    # show what it would write; nothing is launched
.\setup-agent-providers.ps1            # writes ~/.config/opencode/opencode.json
.\claude-local.ps1                     # Claude Code against the local server
```

`setup-agent-providers.ps1` parses the mode table out of `start-llm.ps1` and includes a mode only
when **both its GGUF and its engine's `llama-server.exe` exist**, so it cannot advertise something
that would fail at launch. It merges into the global OpenCode config (existing keys preserved),
names the provider for the engine that serves (`llamacpp`), and backs the old file up as
`opencode.json.bak`. `claude-local.ps1` defaults to `qwen36u35b_ml`; Claude Code needs
`CLAUDE_CODE_ATTRIBUTION_HEADER=0` in `~/.claude/settings.json` or local calls run ~90% slower
(`-FixSettings` writes it).

## Benchmarks, engines, models

| script | use |
|---|---|
| `bench\bench-matrix.ps1` | measures **every `.gguf` found in the models dir**, discovered at run time, so it cannot outlive its models |
| `bench\bench-ab.ps1`, `bench\bench-mtp.ps1` | **obsolete** (they required gemma-4-26B and the ik_llama engine). Kept as the method's record; they refuse and point at `bench-matrix.ps1` |
| `update-llm.ps1` | updates engines; default is `mainline` only. `-Engine ik_llama` / `all` bring the retired one back deliberately |
| `fetch-model.ps1` | resumable, size-verified GGUF download. `tests\download-model.ps1` is a thin wrapper over it |
| `MODELS.md` | provenance: repo, exact bytes, SHA-256, and what is installed on which host |

## Tests

`llm\tests\` holds the quality harness (task set, deny policy, verdict rule, evidence publishing).
Its own self-tests are run by a scratch clone so they cannot disturb this working tree. Two of the
five still fail (deny-gate smuggling routes, derivability guard); the fixes are pending on the
`fix/harness-integrity` branch, and it is deliberately unmerged until its own gate passes.
