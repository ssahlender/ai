# ik_llama.cpp scripts

CPU-only local LLM inference using [ik_llama.cpp](https://github.com/ikawrakow/ik_llama.cpp) (authored by Iwan Kawrakow, packaged by [Thireus](https://github.com/Thireus/ik_llama.cpp)); an optimized fork of llama.cpp featuring custom AVX2/AVX-512 GEMM tiling, optimized quantization formats (IQ\*, K\_P variants), and specialized MoE matrix scheduling.

## Hardware

| Machine | CPU | RAM | OS | Notes |
|---|---|---|---|---|
| HP ProBook (Ryzen) | AMD Ryzen 7 250 (Zen 5) | 32 GB | Windows 11 (native) | AVX512 VNNI VBMI BF16 |
| Work PC (i9) | Intel Core i9-13900 (Raptor Lake) | 64 GB | Debian 12 (bookworm), GLIBC 2.36 | AVX2 + AVX-VNNI; no AVX512 |

Neither machine has a usable GPU. The ProBook's integrated AMD Radeon causes Vulkan OOM crashes; always use `-ngl 0`.

## Scripts

| Script | Purpose |
|---|---|
| `update.sh <machine>` | Download/update ik_llama.cpp (i9) or brew upgrade llama.cpp (macbook-air) |
| `download-models.sh <machine>` | Download GGUF + mmproj files for i9/macbook-air |
| `start.sh <machine> <mode>` | Start llama-server on i9 or macbook-air |
| `setup-agents.sh <machine> [--dry-run]` | Auto-generate OpenCode/Pi/Docker Agent provider config (parses start.sh) and remove stale references to models that are gone |
| `docker-agent-providers.sh [provider] [model]` | Interactive picker & launch Docker Agent with local or remote models |
| `claude-providers.sh [provider] [model]` | Interactive picker & launch Claude Code with local or remote models (shows live n_ctx from `/props`) |
| `.secrets.example` | Template for `~/.secrets` (copy, chmod 600, fill in keys) |
| `ocg-proxy.py` | Anthropic ↔ OpenAI proxy for OpenCode Go (DeepSeek/Kimi/GLM + Claude Code) |
| `bench.sh <machine> <mode>` | Benchmark CPU thread settings with llama-bench (i9) |
| `model-info.sh` | Show on-disk models, file sizes, mmproj status |
| `cleanup-models.sh <machine>` | Remove GGUFs not in active start.sh lineup, whitelist-driven, dry-run by default |

`setup-agents.sh` writes the `ik-llama` provider for OpenCode, Pi, and Docker
Agent (`docker-agent` / `cagent`). Per-model context values are parsed
from `start.sh`. Vision models get `modalities: {input: [text, image], output: [text]}`.
OpenCode gets a conservative `limit.output` of
8192 tokens and:

```json
"compaction": {
  "auto": true,
  "prune": true,
  "reserved": 10000
}
```

This keeps OpenCode's context accounting aligned with the running
llama-server and starts compacting before the context window fills. If you start
llama-server with a non-default `IK_LLAMA_CTX_SIZE`, rerun setup with the same
override so OpenCode uses the correct context window:

```bash
IK_LLAMA_CTX_SIZE=32768 ./setup-agents.sh i9
IK_LLAMA_CTX_SIZE=32768 ./start.sh i9 Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q6_K_P
```

Use `OPENCODE_OUTPUT_LIMIT=<tokens>` only to change OpenCode's reserved output
budget for context accounting. Use `OPENCODE_COMPACTION_RESERVED=<tokens>` only
when testing a different compaction buffer.

Pi config is written to `~/.pi/agent/models.json` with `api:
"openai-completions"`, `contextWindow`, and `maxTokens` for each local model.

Docker Agent (`cagent`) config is registered in `~/.config/cagent/config.yaml`
with the `ik-llama` provider (`http://localhost:9080/v1`), and credentials
(`OPENCODE_API_KEY`, `OPENROUTER_API_KEY`, `NVIDIA_API_KEY`) are synced to
`~/.config/cagent/.env` (mode 0600).

**Model names.** There are no short aliases. A mode, an OpenCode/Pi model id and the
Claude Code model name are all the GGUF file name without `.gguf` (for example
`ik-llama/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q6_K_P`). `start.sh` is the single source of truth:
`setup-agents.sh`, `cleanup-models.sh`, `model-info.sh` and `bench.sh` all read the
list from its `MODES` entries.

**Picking a model without typing the name.** Run `./start.sh i9` (or `./bench.sh i9`) with no mode in a
terminal for a numbered menu, or pass the number from that list (`./start.sh i9 2`). Numbers follow the
order of `MODES` in `start.sh`, so they shift when the lineup changes; the stem stays stable and is what
the agent configs use. Outside a terminal, no mode prints the list and exits.

**Stale settings cleanup.** Each `setup-agents.sh` run regenerates the `ik-llama`
provider, so models that left `start.sh` (or are not on disk) disappear from it. It also
removes dangling `ik-llama/<id>` references that would otherwise break the agent at
startup: OpenCode's `model`, `small_model` and per-agent `model`/`small_model`, Pi's
`defaultModel`, and Docker Agent's `default_model`. It prints everything it removed and does not touch other providers or
unrelated settings. Use `--dry-run` to preview. It refuses to run (and changes nothing)
when no model is on disk, so an unmounted models directory cannot wipe your config.

### Quick start: ProBook (Native Windows PowerShell)

On Windows, ProBook runs natively via the scripts in `llm/` (see `llm/README.md`):

```powershell
pwsh llm\update-llm.ps1
pwsh llm\fetch-model.ps1 qwen36u35b_ml
pwsh llm\setup-agent-providers.ps1
pwsh llm\start-llm.ps1 qwen36u35b_ml
```

Benchmark thread settings:

```powershell
pwsh llm\bench\bench-threads.ps1
```

### Quick start: i9

```bash
./update.sh i9
./download-models.sh i9
./setup-agents.sh i9
./start.sh i9 Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q6_K_P   # or: Qwen3.6-35B-A3B-MTP-UD-Q6_K
./cleanup-models.sh i9     # dry-run obsolete GGUF cleanup
```

All i9 start modes default to `IK_LLAMA_THREADS=8` and `IK_LLAMA_THREADS_BATCH=24`. Override these only for explicit benchmark tests.

### Quick start: MacBook Air M4

```bash
brew install llama.cpp             # prerequisite (once)
./download-models.sh macbook-air
./setup-agents.sh macbook-air
./start.sh macbook-air Qwen3.6-27B-Uncensored-HauhauCS-Aggressive-IQ4_XS   # daily: 27B dense IQ4_XS, 32K ctx
./start.sh macbook-air Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-IQ4_NL   # general: 35B MoE IQ4_NL, 16K ctx
./start.sh macbook-air Qwen3-Coder-30B-A3B-Instruct-IQ4_NL  # coding: 30B MoE IQ4_NL, 32K ctx
```

All Mac modes use Metal GPU (`-ngl 99`) with 4 threads. Same HF repos and mmproj as i9.

> **The Mac's daily driver is Ollama, not this path**; see `../ollama/README.md`.
> This GGUF/Metal path is the alternative. Its Mac lineup predates the memory
> ceiling measured on that machine (a 17.6 GB model OOM'd at 8K context; the
> guard aborts at 16.9 GB), so if you use it there, prefer `IQ3_M` (14.38 GiB)
> or `Q2_K_P` (13.95 GiB) from the same repo; both recorded with sizes and
> hashes in `../llm/MODELS.md`.

For OpenCode edit loops where "Preparing write" feels slow, first try the same coder
model with a smaller active context:

```bash
IK_LLAMA_CTX_SIZE=32768 ./start.sh i9 Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q6_K_P
```

Use the normal 128K default again when the session really needs the extra context.

Benchmark thread settings:

```bash
./bench.sh i9 Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q6_K_P
./bench.sh i9 all
BENCH_THREADS="6 8" BENCH_THREADS_BATCH="24 32" ./bench.sh i9 Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q6_K_P
```

To compare results, start with the generated `*-summary.tsv`, then inspect the referenced JSON files. Look for the highest prompt processing throughput (`pp`/prompt tok/s) that does not hurt generation throughput (`tg`/generation tok/s). For OpenCode, prefer the best overall balance over the absolute highest prompt-only score.

Summarize benchmark results:

```bash
./summarize-bench.py bench-results/*-summary.tsv
```

`bench-results/` is ignored by git. Keep benchmark outputs local unless you explicitly want to share them for analysis.

## Models

### ProBook (32 GB RAM)

| Mode | Model | Size | Context | Vision | Notes |
|---|---|---|---|---|---|
| `qwen36u35b` | Qwen3.6-35B-A3B-Uncensored IQ4\_NL | ~16 GB | 32 K | no | 35B MoE, 3B active |
| `qwen3coder30b` | Qwen3-Coder-30B-A3B Q4\_K\_M | ~19 GB | 64 K | no | Dedicated agentic coder, 262K native ctx |

### MacBook Air M4 (24 GB, Metal GPU)

| Mode | Model | Size | Context | Vision | Notes |
|---|---|---|---|---|---|
| `Qwen3.6-27B-Uncensored-HauhauCS-Aggressive-IQ4_XS` | Qwen3.6-27B-Uncensored IQ4\_XS | ~15 GB | 32 K | yes | 27B dense; all params active, daily driver |
| `Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-IQ4_NL` | Qwen3.6-35B-A3B-Uncensored IQ4\_NL | ~16 GB | 16 K | yes | 35B MoE, 3B active, general + vision |
| `Qwen3-Coder-30B-A3B-Instruct-IQ4_NL` | Qwen3-Coder-30B-A3B IQ4\_NL | ~17 GB | 32 K | no | Dedicated agentic coder, 262K native ctx |

Quick start:
```bash
brew install llama.cpp                      # prerequisite
./download-models.sh macbook-air             # pull GGUFs + mmproj
./setup-agents.sh macbook-air                # wire OpenCode + Pi
./start.sh macbook-air Qwen3.6-27B-Uncensored-HauhauCS-Aggressive-IQ4_XS            # daily driver: 27B dense, 32K ctx
```

The 27B dense IQ4\_XS is the smarter general pick; all 27B params active vs 3B MoE for the 35B, and still fits at 32K context on 24 GB unified memory. Use `Qwen3-Coder-30B-A3B-Instruct-IQ4_NL` for focused coding sessions. Same HF repos and mmproj files as i9, just different quants (IQ4\_XS/IQ4\_NL for Mac vs K\_P for i9).

### i9 (64 GB RAM)

| Mode | Model | Size | Context | Vision | Notes |
|---|---|---|---|---|---|
| `Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q6_K_P` | Qwen3.6-35B-A3B-Uncensored Q6\_K\_P | ~31 GB | 128 K | yes | 35B MoE quality baseline + vision |
| `Qwen3.6-35B-A3B-MTP-UD-Q6_K` | Qwen3.6-35B-A3B MTP UD-Q6\_K (vanilla, unsloth) | ~30 GB | 128 K | no | MTP speculative decoding, plus `suffix` drafting by default (edit loops ~2x, see the suffix section): MTP alone ~+25% tg on code, +4-11% on prose; not the uncensored finetune; no vision (`--mmproj` unsupported with MTP) |

**Dropped 2026-10-07** (lowest agent score, no quality edge, slowest; see the rounds below). Measured while it was in the lineup: Qwen3-Coder-Next 80B-A3B (UD-Q3_K_M, ~36 GB) ran at ~98 pp tok/s and ~16 tg tok/s at 8/24, about 20% slower than the 35B-A3B models due to the larger model footprint (same 3B active params, more bytes to stream). Context set to 128K for long agent sessions; prompt-cache RAM capped via `cram`.

NVIDIA's Nemotron-3.5-Lightning-30B-A3B was tried and dropped: its architecture interleaves Mamba-2 (SSM) layers with MoE and attention layers, which ik_llama.cpp (an AVX2/quant-kernel-focused `llama.cpp` fork) doesn't implement; it fails to load with `unknown model architecture: 'nemotron_h_moe'`. Confirmed via direct load test, not just a version mismatch.

**`-ub`/`--ubatch-size` default raised to 1024** (`IK_LLAMA_UBATCH` env override) after a sweep on a 35B-A3B Q5_K_M (since dropped from the lineup) showed a free ~2.5% pp gain (135.8 → 139.1 t/s at ub=1024 vs the previous default of 512) with `tg` unaffected. No GPU-style cliff at small ubatch values on this AVX2 CPU path, unlike reports on GPU/ROCm backends.

### MTP speculative decoding (Qwen3.6-35B-A3B)

Qwen3.6 ships multi-token-prediction layers; ik_llama.cpp runs them with
`--spec-type mtp:n_max=N,p_min=0.0` (the `Qwen3.6-35B-A3B-MTP-UD-Q6_K` mode uses `n_max=1`).
The weights come from `unsloth/Qwen3.6-35B-A3B-MTP-GGUF`; `download-models.sh` stores the file
as `...-MTP-UD-Q6_K.gguf` because unsloth's non-MTP repo ships a different file with the
same upstream name.

Measured 2026-10-06 on the i9 (ik_llama `main-b5352-b3e6773`, 8/24 threads, ubatch 1024, q8_0 KV,
256 generated tokens, greedy). Each prompt is one column; `code` and `code2` are two different coding prompts.
Q6\_K baseline and `n_max=1` are means of 3 runs, Q4\_K\_XL means of 2; `n_max=2` and `n_max=3` are **single runs**.
Run-to-run spread was about 1 t/s or less. Percentages are against the mean baseline of the same quant.

| Quant / setting | code | code2 | German prose | Draft acceptance (code / code2 / prose) |
|---|---:|---:|---:|---|
| Q6\_K, no MTP | 20.2 t/s | 20.3 | 20.3 | - |
| Q6\_K, MTP `n_max=1` | **25.3** (+25%) | **25.3** (+25%) | **22.6** (+11%) | 90% / 86% / 67% |
| Q6\_K, MTP `n_max=2` | 25.0 (+24%) | 24.3 (+20%) | 20.1 (-1%) | 77% / 79% / 54% |
| Q6\_K, MTP `n_max=3` | 24.3 (+20%) | 10.6 (-48%, not reproduced) | 18.7 (-8%) | 69% / 74% / 41% |
| Q4\_K\_XL, no MTP | 22.5 | 21.9 | 22.8 | - |
| Q4\_K\_XL, MTP `n_max=1` | 27.7 (+23%) | 27.7 (+27%) | 23.8 (+4%) | 90% / 86% / 66% |

What this means:

- **`n_max=1` improved generation in every measured run; larger drafts add nothing on code and lose on prose.**
  Verifying more drafted tokens per step wakes more experts on a CPU MoE and reads more weights, so extra
  draft tokens stop paying for themselves. The one `n_max=3` result of 10.6 t/s (`code2`) was a single run
  that was not repeated; treat it as a warning, not a measurement.
- **The gain is about +25% on code and +4-11% on prose**, not the 1.5-2x on the model card.
- **Prompt processing drops about 16%** (mean 77 to 65 t/s over all prompts), which matters for long agent contexts.
- **Q4\_K\_XL is only ~10% faster than Q6\_K**, so generation is not purely bandwidth-bound here. We stay at the Q6 tier.
- **Not the uncensored finetune.** This is vanilla Qwen3.6. The HauhauCS 35B-A3B build has no MTP layers in the GGUF
  (only its 27B dense build does, which is too slow on CPU). Quality was not compared, only speed.
- **Production flags cost some of the gain.** The same mode started through `start.sh` (128K ctx, prompt cache,
  context shift) generated at about 23 t/s on two chat requests at temperature 0.2, with the same ~90% draft
  acceptance. That is about +15% against the 20.3 t/s baseline above (different prompts and sampling, so only
  indicative). Expect +15-25% on code in practice, not the harness figure.
- **Chat template.** The MTP mode uses the GGUF's embedded template, not `qwen3-template.j2` (which patches
  Claude CLI's late system messages for the HauhauCS/Qwen finetunes). Checked on 2026-10-06: an OpenAI-style tool
  call round trip works (call emitted, result consumed, answer produced), and a system message placed after other
  messages is accepted without error (its instruction was not honoured, though). **Not verified:** Claude Code
  itself against this mode, and prompt-cache reuse / context shift once the 128K window actually fills.
- `llama-bench` ignores speculation, so `bench.sh` reports the non-MTP speed for this mode. Use a server run
  (`/completion` timings: `draft_n`, `draft_n_accepted`) to measure MTP.

### Agent reality round (2026-10-06)

Five small real tasks in throwaway Python repos (parsing, config merging, a CLI flag, a shell-quoting refactor), solved end to end by a coding agent in a sandbox (read-only filesystem, own writable directory) and scored by hidden pytest files that run only after the agent finishes. Tasks were proposed by Codex (3) and Claude (2); each was validated first (the unmodified project fails the hidden tests, the reference solution passes). OpenCode ran with a minimal isolated config; Claude Code ran with `--bare` through the max-tokens proxy. 50 runs in total, 10-minute cap, no timeouts. The harness is not part of this repository.

Pass (P) / fail (F) per sample; most cells have two samples:

| Task | MTP + OpenCode | MTP + Claude Code | HauhauCS + OpenCode | HauhauCS + Claude Code | Coder-Next + OpenCode | Coder-Next + Claude Code |
|---|---|---|---|---|---|---|
| env-file parser (bugfix) | FP | PP | PP | P | PP | P |
| recursive config merge (feature) | FF | FF | FF | F | FF | F |
| shell-quote refactor | PP | PP | PP | P | PP | P |
| logfmt parser (bugfix) | PP | PF | FP | P | PF | P |
| report `--format json` (feature) | PF | PP | PP | P | FF | F |
| **Passed** | **6/10** | **7/10** | **7/10** | **4/5** | **5/10** | **3/5** |
| Mean time / tool calls | 250 s / 13.8 | 186 s / 12.7 | 204 s / 12.0 | 210 s / 11.2 | 251 s / 11.1 | 179 s / 8.6 |

By model, both agents together: HauhauCS **11/15 (73%)**, MTP **13/20 (65%)**, Coder-Next **8/15 (53%)**. By agent: OpenCode 18/30 (60%), Claude Code 14/20 (70%).

- **Run-to-run noise is large:** in 5 of the 20 cells that were sampled twice, the same model and agent gave opposite results on the same task. Differences of one or two tasks between setups are noise.
- **Coder-Next 80B is lowest with both agents** (53% against 65-73%) and shows no advantage anywhere: not on the general rounds, not here. The gap is within noise for this sample size, but the direction is the same in all three rounds, it generates slowest (~16 t/s) and needs 34 GB of RAM, so the evidence favours dropping it.
- **HauhauCS and vanilla MTP are indistinguishable on agent work** (73% vs 65%, one noisy task apart). MTP's speed gain therefore costs no measurable quality here either.
- **Claude Code works against the local MTP mode** through the proxy (no protocol failures, 2-16 tool calls per task). It scored 70% against OpenCode's 60%, ahead or equal on all three models, but that is a small difference and confounded: Claude Code `--bare` sends ~1.4K tokens of prompt against ~12K for OpenCode, and the two use different tools. The prompt-size difference itself is real and measured (cold start ~16 s against ~2.3 min on this CPU).
- **The config-merge task is a floor:** it failed in all 10 runs, every model and both agents. The prompt states the clause explicitly ("the deletion rule also applies inside override dictionaries that replace a scalar or introduce a new key"), so the task is fair, but it cannot discriminate between setups.
- **All failures were missed explicit instruction details** (an error message to raise, "keys without a value", an unknown-format exit code), the same weakness as in the quality rounds.
- **Test fairness:** one hidden test (`--format=json` equals syntax) was not promised by the task prompt; it was removed mid-round and the earlier runs were re-scored from their saved work directories (one run flipped to pass).

### Prompt cache and slot persistence (measured 2026-10-06)

Cold prefill is the expensive part on this CPU (about 105-120 tokens/s, so a 13K-token context costs 2+ minutes and 50K tokens about 8). Measured with a 12.9K-token repo context and one agent-style conversation, single runs, tiny answers so the time is almost all prompt processing:

| Wall time | HauhauCS 35B | MTP 35B | Coder-Next 80B |
|---|---:|---:|---:|
| Cold prefill | 123.7 s | 145.0 s | 147.1 s |
| Same prefix, next question | 1.1 s | 1.5 s | 1.3 s |
| **First line of the system prompt changed** | **121.7 s** | **140.3 s** | **154.7 s** |
| Back to the original prefix | 0.9 s | 1.3 s | 1.3 s |
| Save slot / file size | 0.56 s / 1.4 GB | 0.61 s / 0.9 GB | 0.97 s / 1.7 GB |
| **After server restart + restore: first request** | **0.6 s** | **0.9 s** | **1.0 s** |

- Within a session the existing prompt cache already works: a stable prefix costs about 1 s per turn, and the RAM prompt cache (`-cram`) also remembers a previous prefix, so alternating between two sessions is cheap.
- Anything that changes near the start of the prompt (a timestamp, a per-message hash) makes every turn cost the full cold prefill, about 100 times slower. Keep volatile content at the end of the prompt.
- Saving a slot to disk and restoring it after a restart brings back the whole context in about a second, with the vision projector loaded and with MTP speculative decoding. It only helps if the next prompt starts with exactly the same tokens.

```bash
# start with a slot directory (start.sh appends IK_LLAMA_EXTRA_ARGS last)
IK_LLAMA_EXTRA_ARGS="--slot-save-path $HOME/.cache/ik-llama-slots" ./start.sh i9 <mode>
curl -s -X POST "http://localhost:9080/slots/0?action=save"    -d '{"filename":"myrepo.bin"}'
curl -s -X POST "http://localhost:9080/slots/0?action=restore" -d '{"filename":"myrepo.bin"}'   # after a restart, same model and flags
```

What the agents send first (captured through a fake endpoint, two runs a minute apart, from a git repository):

| Agent | Prompt start | Verdict |
|---|---|---|
| OpenCode | ~36K-char system block (tools, skills, repo `AGENTS.md`), `Today's date` and the working directory near the end | stable; a new day costs one partial re-prefill from the date line |
| Pi | ~24K-char system block, 26 tools, no date or time | stable |
| Claude Code (`--bare`) | `x-anthropic-billing-header: cc_version=...<hash>` as the very first line; the hash depends on the user's message | **breaks the cache every turn** unless `CLAUDE_CODE_ATTRIBUTION_HEADER=0`; `claude-providers.sh` now sets it |

Not covered: long sessions where an agent compacts or truncates its history (that also changes the prefix), and what happens when two agents share one server slot.

### Quality checks (2026-10-06)

Three rounds of small automatic tests on the i9, through `start.sh` with the production flags: non-thinking mode, temperature 0.2, single runs unless noted. Round 3 was proposed independently by three AI reviewers (Codex, Agy, Claude) to avoid one author's blind spots; every checker was validated against reference answers first, and generated scripts run in a bubblewrap sandbox (read-only filesystem, no network). The test harness is not part of this repository.

| Round | What it covers | HauhauCS 35B Q6\_K\_P | MTP 35B Q6\_K | Coder-Next 80B Q3\_K\_M |
|---|---|---:|---:|---:|
| 1: simple (11) | arithmetic, logic, code tracing, small coding, German, formats, tool call | 9/11 | 10/11 | not run |
| 2: harder (12) | behaviour-tested code, 6K-token log needle, puzzles, JSON/YAML, 2-step agent | 9/12 | 9/12 | not run |
| 3: mixed (13) | 3 agent tasks, strict-contract refactor, shell/config reasoning, German, SOC triage, executed bash, k8s, Terraform | 11/13 | **13/13** | 11/13 |
| Speed, short answers | | 21.6 t/s | 25.1 t/s | 16.1 t/s |

Round 3 bash script task: HauhauCS 2/2 samples, MTP 1/2, Coder-Next 0/2 (the losing scripts printed `count<TAB>name` instead of `name<TAB>count`). The table counts the first sample.

- **MTP costs no measurable quality.** It scored equal or higher in every round. With 11-13 questions and single runs this is evidence, not proof; one flipped question changes the totals.
- **Agent behaviour depends on the system prompt.** With no system prompt both 35B models never called tools and guessed (0/5); with a one-line agent system prompt they passed 5/5 and followed 3-step lookups. In round 3 all three models passed the three agent tasks (error recovery, concurrent-update conflict, two prompt injections) with such a prompt. Test agents with the harness's real system prompt.
- **Coder-Next 80B was not better on general tasks** (11/13) and about 30% slower than the 35B models; it was dropped on 2026-10-07 after the agent round.
- **Shared weaknesses are instruction details, not knowledge:** both 35B models ignored an explicit "slash date is US month/day" instruction (0/4) and added a time to a date (0/4); one model wrote evidence ids as numbers; one used a forbidden word; and without step-by-step reasoning a short code-tracing question was answered wrongly (15/16 instead of 23; correct when asked to reason).
- **HauhauCS specifics:** it failed the strict lazy-batching contract and, in round 1, invented an explanation for a fictional country instead of saying it does not exist (one prompt, so only a hint).
- **Test-harness lesson:** three of the first checkers were wrong (a command deny-list blocked legitimate `trap 'rm -f "$tmp"'`, an over-strict tool-call order, a misreading of `>=` as a redirect). Validate every checker against reference answers, and sandbox instead of deny-listing.

## Binaries

Downloaded automatically by `update-*.sh`. Correct build for each machine:

| Machine | Build pattern |
|---|---|
| ProBook (Windows) | `*-bin-win-cpu-x64-avx512_vnni_vbmi_bf16.zip` |
| i9 (Linux) | `*-bin-ubuntu-x64-avx2.zip` |

Note: Use the generic `avx512_vnni_vbmi_bf16` build on ProBook, **not** `znver5`; the znver5 build crashes with Qwen3 MoE models.

## Flag reference

| Flag | Value | Purpose |
|---|---|---|
| `-ngl 0` | 0 | CPU-only, disables GPU offload |
| `--threads` | machine default | Generation threads. Override: `IK_LLAMA_THREADS` |
| `--threads-batch` | machine default | Prompt processing threads. Override: `IK_LLAMA_THREADS_BATCH` |
| `--parallel` | 1 | Keep one full-context slot and preserve prompt-cache locality. Override: `IK_LLAMA_PARALLEL` |
| `--ctx-size` | 32768–131072 | Context window |
| `IK_LLAMA_CTX_SIZE` | env override | Override the per-model context size for fast OpenCode edit loops |
| `IK_LLAMA_CRAM_MB` | env override | Override the per-model prompt-cache RAM limit |
| `-sps 0.5` | 0.5 | Slot prompt similarity for cache reuse |
| `-cram <MB>` | 8192–32768 | Prompt-cache RAM limit |
| `-crs 0.5` | 0.5 | Cache similarity threshold |
| `-ctk q8_0` | q8_0 | Quantize K cache (requires flash attention) |
| `-ctv q8_0` | q8_0 | Quantize V cache (requires flash attention) |
| `-dt 0.1` | 0.1 | Defragmentation threshold |
| `--host <ip>` | 127.0.0.1 | Listen interface (override with IK_LLAMA_HOST) |
| `--jinja` | — | Enable Jinja templates (required for tool calling) |
| `--context-shift on` | on | Explicitly enable context shift (soft-rolls old KV instead of erroring when context fills) |
| `-rea off` | off | Disable thinking/reasoning mode |
| `--temp` / `--top-p` / `--top-k` | 0.2 / 0.8 / 20 | Conservative i9 Qwen sampling for OpenCode tool-call JSON reliability. Override: `IK_LLAMA_TEMP`, `IK_LLAMA_TOP_P`, `IK_LLAMA_TOP_K` |
| `-v` | — | Verbose output (shows tok/s, timing) |
| `--mlock` | — | Lock model in RAM (i9 only, prevents swapping) |
| `--mmproj <file>` | — | Multimodal projector GGUF for vision (Qwen3.6; not usable together with MTP) |

### Qwen3 sampling

```
--temp 0.6 --top-p 0.95 --top-k 20
```

Recommended by the Qwen3 technical report for thinking/chat mode.

## Performance

### ProBook (Ryzen 7 250, Zen 5, AVX512, Windows 11)

Benchmarked with `p=2048 n=128 r=3` via llama-bench.exe (x64 AVX512 VNNI VBMI BF16 build):

| Mode | Threads (gen/batch) | pp2048 (t/s) | tg128 (t/s) |
|---|---|---:|---:|
| `qwen36u35b` IQ4\_NL | **8 / 8** | **109.6** | 12.9 |
| `qwen36u35b` IQ4\_NL | 12 / 12 | 100.2 | **13.9** |
| `qwen36u35b` IQ4\_NL | 8 / 16 | 95.0 | 12.9 |
| `qwen36u35b` IQ4\_NL | 16 / 8 | 85.1 | 11.7 |
| `qwen3coder30b` Q4\_K\_M | — | — | — | benchmarks pending |

Default startup uses `THREADS=8 THREADS_BATCH=16`. Use `IK_LLAMA_THREADS=8 IK_LLAMA_THREADS_BATCH=8` for maximum qwen prompt throughput.

**ProBook vs i9 comparison:**

| | ProBook (Zen 5, 32 GB) | i9-13900 (Raptor Lake, 64 GB) |
|---|---:|---:|
| pp2048 (t/s) | ~100–110 | ~122–131 |
| tg128 (t/s) | ~12–13 | ~23–26 |

Prompt processing is close (~80% of i9) thanks to AVX512. Token generation is roughly half, memory bandwidth limited by 32 GB laptop DDR5 vs 64 GB desktop DDR5.

- First message with long system prompt: ~5–10 s (cache cold, mmap)
- Subsequent messages: ~2–3 s (cache hit)

### i9-13900 (Raptor Lake, AVX2)

Active model throughput at the default `8/24` thread setting:

| Mode | pp2048 (t/s) | tg128 (t/s) | Notes |
|---|---:|---:|---|
| `Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q6_K_P` | ~122.8 | ~22.6 | Quality baseline + vision |

All models are well above the interactive threshold for OpenCode tool loops. The MTP mode is faster for generation than these numbers suggest (see the MTP section; `llama-bench` cannot show it).

### i9 speed notes

The i9 is CPU-only and AVX2-only, so dense 20 GB-class models are mostly memory-bandwidth bound. Qwen3-Coder-Next 80B-A3B, Ornith-1.0 35B, Qwopus3.6 and SuperGemma4 were removed (Coder-Next on the agent rounds, the others on quality checks).

- Start with `Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q6_K_P` for general use (vision, uncensored), or `Qwen3.6-35B-A3B-MTP-UD-Q6_K` for faster generation (suffix + MTP: ~2x on edit loops, +5-25% elsewhere).
- All i9 modes default to 128K context. Treat that as an emergency ceiling and keep working context at 16K to 32K through agent-side compaction. Rerun provider setup with the same `IK_LLAMA_CTX_SIZE` override when changing the server window.
- Use `IK_LLAMA_THREADS=8` and `IK_LLAMA_THREADS_BATCH=24` as the default i9 startup point.
- Avoid `IK_LLAMA_THREADS=10` and `12`; benchmarks were consistently worse than `6` and `8`.

### ik_llama.cpp vs standard llama.cpp (i9, Qwen3-Coder-Next-UD-Q3_K_M, b9789)

Measured on the same model (Qwen3-Coder-Next UD-Q3\_K\_M) with `p=2048 n=128 r=3`:

| Engine | Threads | pp2048 (t/s) | tg128 (t/s) |
|---|---|---:|---:|
| ik_llama.cpp (Thireus fork) | 8 gen / 24 batch | **98.6** | 15.8 |
| standard llama.cpp b9789 | 8 | 45.4 | 15.8 |
| ik_llama.cpp | 16 gen / 24 batch | 93.1 | 14.2 |
| standard llama.cpp b9789 | 16 | 46.4 | 14.7 |

**Prompt processing: ik_llama is ~2.1× faster.** Token generation is identical (both are memory-bandwidth bound). Standard llama.cpp b9789 correctly auto-detected the i9 as Alder Lake and loaded `libggml-cpu-alderlake.so`, so this is a fair comparison; not a configuration gap.

The PP speedup matters for coding sessions: it determines how fast tool results, file reads, and `/compact` requests are ingested. Some of ik_llama's IQ\*/K\_P AVX2 kernel improvements have been contributed back upstream over time (IQ1/IQ2/IQ3/IQ4 quant formats, some kernel patches), but the batch processing gap above shows significant optimizations remain fork-only.

### Completed ProBook benchmark notes

Benchmarked 2026-06-29 with ik_llama.cpp b4958 (`x64-avx512_vnni_vbmi_bf16`), `p=2048 n=128 r=3`.

**qwen36u35b (IQ4\_NL, 19.5 GB):**

| gen/batch | pp2048 (t/s) | tg128 (t/s) |
|---|---:|---:|
| 8 / 8 | **109.6** | 12.9 |
| 12 / 12 | 100.2 | **13.9** |
| 12 / 16 | 100.4 | 13.4 |
| 8 / 16 | 95.0 | 12.9 |
| 16 / 16 | 96.2 | 11.7 |
| 16 / 12 | 97.0 | 10.2 |
| 16 / 8 | 85.1 | 11.7 |

**qwen3coder30b (Q4\_K\_M, ~19 GB):** benchmarks pending; run via `llm/bench/bench-threads.ps1` after download.

Default `8/16` is the best balanced setting for qwen36u35b. Use `8/8` (`IK_LLAMA_THREADS=8 IK_LLAMA_THREADS_BATCH=8`) only if qwen prompt throughput is the priority.

### Completed i9 benchmark notes

`8/24` is the best default. `8/32` drops pp significantly with no tg gain.

**Active models, best rows at `8/24`:**

| Mode | pp2048 (t/s) | tg128 (t/s) | Notes |
|---|---:|---:|---|
| `Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q6_K_P` | 122.8 | 22.6 | Quality baseline + vision |
| `Qwen3-Coder-Next-UD-Q3_K_M` (dropped 2026-10-07) | 92.7 | 16.3 | 80B MoE heavy coder |

**Rejected candidates (historical):**

| Mode | pp2048 (t/s) | tg128 (t/s) | Reason dropped |
|---|---:|---:|---|
| `ornith35q6k` | 122.5 | 23.1 | Good throughput, failed manual quality |
| `Qwen3.6-27B-Uncensored-HauhauCS-Aggressive-Q5_K_P` | - | 3.4 | Dense 27B: too slow on CPU for interactive use (dropped 2026-10) |
| `Qwopus3.6-35B-A3B-v1-Q5_K_M` | 130.9 | 26.4 | Fastest llama-bench numbers, but not good in real use (dropped 2026-10) |
| `supergemma4-26b-uncensored-fast-v2-Q4_K_M` | 129.1 | 23.2 | Not good in real use (dropped 2026-10) |
| `qwen3coderq5km` | 110.6 | 29.8 | Failed manual quality |
| `qwen3coderq8` | 105.8 | 20.7 | Failed manual quality |
| `qwen3coderq6k` | 102.1 | 25.6 | Failed manual quality |
| `glm47flashq5km` | 91.7 | 20.8 | Slower than Qwen MoE, low quality |
| `qwen3fast:q4/q5` | ~33–40 | ~6–7 | Too slow |
| `qwen38b:q4/q5` | ~60 | ~13 | Not competitive with MoE |
| `qwen332b / qwen25coder32b` | ~14 | ~3 | Way too slow on AVX2 |

`bench.sh` takes the same mode names as `start.sh` (GGUF stems; the list is read from `start.sh`, run it without a mode to see them) or `all`. `llama-bench` does not do speculative decoding, so the MTP mode benchmarks at its non-MTP speed; see the MTP section for speculative numbers.

**Benchmark output:** TSV summary files (`bench-results/*-summary.tsv`) are metadata indexes pointing to individual JSON files (one per thread combo). Use `summarize-bench.py` to get throughput numbers:

```bash
./summarize-bench.py bench-results/*-summary.tsv
```

For 128K OpenCode sessions on the i9 with `Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q6_K_P`, start with:

```bash
./start.sh i9 Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q6_K_P
OPENCODE_COMPACTION_RESERVED=24000 ./setup-agents.sh i9
```

To free disk space after rotating models:

```bash
./cleanup-models.sh i9        # dry run — shows what would be removed
./cleanup-models.sh i9 --apply
```

The cleanup script derives the whitelist from `start.sh` MODES automatically; any file not in the active lineup is flagged.

## Key lessons

1. **`-ngl 0` always**: integrated GPU causes Vulkan OOM crashes
2. **Quantized KV cache requires flash attention on**: `-ctv q8_0` is incompatible with `--flash-attn off`; ik_llama.cpp enables FA by default which is correct
3. **Avoid `_XL` variants**: incompatible quantization format with ik_llama.cpp
4. **ProBook: use generic AVX512 build**: `znver5` crashes with MoE models (exit code 29 on any model load, despite `-h` working)
5. **i9 has no AVX512**: Intel fused off AVX-512 on consumer Raptor Lake; use AVX2 + AVX-VNNI build only
6. **Prefill and prefix-cache stability are the true bottleneck on CPU**: decode speed (16–26 t/s) is negligible next to cold prefill at ~100 t/s (ingesting a 50K context cold takes >8 minutes; 128K takes >20 minutes). Practical turnaround in coding agents is dominated by prefix-cache hits (`--cache-reuse`, single slot `IK_LLAMA_PARALLEL=1`, stable system prompts, static tool definitions).
7. **128K context is an emergency ceiling, not routine operating depth**: operate at 16K–32K with agent-level harness compaction (e.g. OpenCode reserving 10,000 tokens to prune old tool outputs) rather than letting contexts inflate to 100K+.
8. **Hybrid linear attention in Qwen3-Coder-Next 80B-A3B**: combines Gated DeltaNet (linear recurrent layers) with only 12 full-attention layers. This provides O(1) memory per linear layer at deep context, explaining how an 80B-class model runs in 64 GB RAM. Note that recurrent hidden state cannot be shifted by server-side context shift, making harness-side compaction strictly mandatory.
9. **Claude Code attribution header causes a silent slowdown**: Claude Code puts `x-anthropic-billing-header: cc_version=...bXX; ...` as the very first line of the system prompt, and the suffix is a hash of the user's message (captured 2026-10-06: `hi` always gives `bc6`, other prompts give other values). Byte zero of the prompt therefore changes whenever the message changes, so the local server's prompt cache cannot match and every turn re-prefills the whole context (measured: ~120 s instead of ~1 s per turn at 13K tokens). `CLAUDE_CODE_ATTRIBUTION_HEADER=0` removes the line; `claude-providers.sh` now sets it for every launch. OpenCode and Pi were checked the same way and have no per-turn value at the start of their prompts (OpenCode has a date line near the end of its system block, so a new day costs one partial re-prefill).
10. **The "Empty Answer" thinking budget trap**: on reasoning models, small `max_tokens` budgets (e.g. 32 or 64) spend every token in `reasoning_content` and return empty `content: ""`. Appending `/no_think` does not suppress thinking on these templates. Either provide generous token headroom (1024+) or turn off internal thinking server-side via `-rea off` (which cuts turn latency 50–80% for coding).
11. **MoE active-parameter ceiling vs dense models**: 35B-A3B MoE routes ~3.2B active parameters per token. While fast on DDR5 (~24 t/s), dense 27B–32B models have full parameter depth on every token. For complex logic, speculative decoding (prompt lookup / n-gram drafting) on dense models can narrow the generation gap without model degradation.
12. **Vision requires mmproj**: Qwen3.6 models support image input (not combined with MTP) when `--mmproj <file>.gguf` is passed to llama-server. The mmproj file is downloaded alongside the model GGUF. GLM-4.7-Flash is text-only.
13. **One server slot per active agent**: `--parallel 2` divides the configured context between slots, while unrelated sessions evict each other's cached prefixes. Keep the default `IK_LLAMA_PARALLEL=1`; use separate server instances when concurrent agents need full context and stable cache reuse.
14. **No YARN for Qwen3 instruct models**: Qwen3 instruct supports 128K context natively. YARN (`--rope-scaling yarn --yarn-orig-ctx 32768`) was a Qwen2.5-era workaround for 32K base models. On Qwen3 it is redundant and silently disables context shift in ik_llama, causing hard 500 errors when context fills. All Qwen3-family modes have YARN removed.
15. **`--context-shift on` is explicit**: set explicitly in `start_model()` as a guard against version differences. Note that harness-side compaction should always be primary.
16. **ProBook: `bench.sh` uses JSON output, not CSV**: `llama-bench.exe` embeds a null byte in the `cpu_info` CSV field, which silently truncates every data row (no performance numbers captured). `-o json` is used instead. `summarize-bench.py` reads both formats.
17. **ProBook: native Windows execution**: WSL has been retired on ProBook. All model execution and benchmarks now run natively on Windows via PowerShell scripts in `llm/`.
18. **ProBook: clear Windows standby page list between benchmark runs**: after each ~20 GB model run, Windows retains model pages in the standby list. Switching to a different model before the standby list is evicted causes mmap to fail with exit 5. In native Windows benchmarks (`llm/bench/`), the standby list is cleared between runs.

## Debian 12 / GLIBC 2.36 compatibility

Homebrew binary bottles are built on Ubuntu 24.04 (GLIBC 2.38). They won't run
on Debian 12 (GLIBC 2.36). Affected: node, pi, and any brew formula that ships
a compiled binary.

**Symptoms:**
```
/home/linuxbrew/.linuxbrew/opt/node/bin/node: /lib/x86_64-linux-gnu/libm.so.6:
version `GLIBC_2.38' not found
```

**Fix, wrapper script (no root, no npm):**
`pi-install.sh` auto-detects the glibc issue and creates `~/.local/bin/pi`,
a wrapper that runs pi's JS via the system node, bypassing brew's broken
node. Brew still manages pi upgrades; the wrapper auto-picks the latest version.

For other brew formulae with the same issue, either build from source
(`brew install --build-from-source <formula>`) or install via the system package
manager instead of brew.

Ubuntu 24.04 and macOS are unaffected, brew bottles work natively.

## Reasoning round (2026-10-07)

MTP model, round-3 battery (13 tasks), 2 samples per arm, `max_tokens` 1500 (off), 3000 (scaffold), 6000/8000 (thinking). Thinking was enabled with `IK_LLAMA_EXTRA_ARGS='-rea on --reasoning-budget N'`.

| Arm | Passed (2 samples) | Total time of 2 runs |
|---|---|---|
| reasoning off (baseline) | 11/13, 11/13 | 222 s |
| step-by-step scaffold prompt | 9/13, 9/13 | 496 s |
| thinking, budget 512 | 7/13, 10/13 | 1753 s |
| thinking, budget 2048 | 10/13, 10/13 | 1992 s |

- **Thinking does not pay off overall.** It is 8-9x slower and not better than off. It fixed one task (A-05, negative rules in an incident summary: 0/2 -> 2/2 at both budgets) but broke others (K-02 terraform validation 2/2 -> 0/2 at 2048, A-06 PodSpec 2/2 -> 0/2 at 512, K-01, C-06).
- **The scaffold prompt hurts:** C-04 and C-05 (exact-JSON tasks) went 2/2 -> 0/2.
- **A-04 (executed bash script) fails in every arm,** so reasoning does not fix it.
- **Recommendation:** keep `-rea off` (the `start.sh` default). Use `-rea on --reasoning-budget 2048` only for a single task that is a known failure with it off, such as negative-rule summaries.
- Caveat: 2 samples, one model; run-to-run noise (think512: 7 vs 10) is about as large as the differences.

## Suffix drafting on top of MTP (2026-10-07)

`start.sh` now starts the MTP mode with a two-stage chain, `--spec-type suffix:... --spec-type mtp:n_max=1,p_min=0.0` (the self-speculation stage must come first). The `suffix` stage drafts from text already in the context, so it pays off when the output repeats the input (edit loops, "rewrite this file with one change"). Drafts are verified by the model, so output is unchanged apart from sampling noise.

Decode speed, tokens/s (2 runs each, `max_tokens` 2500, same prompts on builds b5352 and b5409):

| Setup | Edit a 260-line file | Prose | New code |
|---|---|---|---|
| no drafting | 20 | 20 | 20 |
| MTP alone | 23 | 23 | 24-25 |
| `ngram-mod` alone | 37-40 | 20-22 | 15 (slower) |
| `ngram-mod` + MTP | 40 | 22 | 17-18 (slower) |
| **`suffix` + MTP (default now)** | **50-53** | 21-24 | 22-28 |

`ngram-mod` is not worth it (loses on new code). `IK_LLAMA_SPEC` overrides the mode's speculation flags (raw flags; `none` turns it off), e.g. `IK_LLAMA_SPEC='--spec-type mtp:n_max=1,p_min=0.0' ./start.sh i9 2` for the previous MTP-only setup. Not yet re-run: the agent reality round with this chain, and prompt-processing speed (MTP costs about 16%).

### Suffix drafting on HauhauCS, agent round with the chain, Qwen3.8-27B (2026-10-07)

- **HauhauCS gets no drafting by default, and the server refuses it with vision on.** With `--mmproj` loaded the server logs `speculative decoding is not supported by multimodal, it will be disabled`, so `IK_LLAMA_SPEC` has no effect there. `IK_LLAMA_NO_MMPROJ=1` starts the mode without the projector; then `IK_LLAMA_SPEC='--spec-type suffix:n_max=16,n_min=2,suffix_min_match_len=5,suffix_max_depth=64'` works. Measured (tokens/s, edit / prose / new code): no vision + suffix **50-54** / 21 / 20-31, against 22 / 22 / 22 with vision and no drafting. Choose per task: vision, or 2x on edit loops. The default stays with vision, without drafting.
- **Agent reality round with the suffix + MTP chain** (MTP model, 20 runs, both agents, same five tasks): 15/20 (OpenCode 8/10, Claude Code 7/10), against 15/22 with MTP alone. Same failures (the config-merge floor), no protocol errors, wall time about equal (Claude Code 153 s vs 183 s, OpenCode 258 s vs 245 s average). The chain costs no quality; the gain shows on long rewrites, not in agent loops.
- **Qwen3.8-27B dense (HauhauCS MTP release, Q4_K_P, 16.4 GiB): not usable on the i9.** It loads in ik_llama (`qwen35` arch) but runs prompt processing at 19 tokens/s and decoding at 3.8 tokens/s (`llama-bench`, 24/8 threads), against about 120 and 22 for the 35B-A3B models. A dense model streams all weights per token; embedded MTP cannot close a 5x gap, so the MTP server run was cancelled and the file deleted. The FastMTP sidecar needs a patched mainline llama.cpp. A GPU or Apple Silicon is the right place for this model.

### KV cache q4_0 vs q8_0 (2026-10-07)

MTP model with the default suffix + MTP chain, `IK_LLAMA_EXTRA_ARGS='-ctk q4_0 -ctv q4_0'` against the default q8_0. Three facts hidden at 20/50/80% depth of a code/doc haystack, one question asks for all three plus their sum; 7 runs per setting (8K to 70K tokens, two seeds up to 36K), plus the 13-task battery twice.

| | q8_0 | q4_0 |
|---|---|---|
| Needle retrieval (7 runs x 4 answers) | 28/28 | 28/28 |
| Battery (2 samples) | 11/13, 12/13 | 10/13, 11/13 |
| Prompt processing at 70K tokens | 48.8 tok/s | 45.6 tok/s |
| Decode at 70K tokens | 12.5 tok/s | 13.2 tok/s |
| Prompt processing / decode at 8-36K | same within 5% | same within 5% |

q4_0 loses no retrieval up to 70K tokens, but it gains no speed on this CPU (the dequantization costs about what the smaller cache saves) and the battery is one task lower in both samples, which is within the noise seen elsewhere but is not a win. The only benefit would be memory, and the hybrid Qwen3.6 models keep full attention in only a quarter of their layers, so the cache is small to begin with. **Keep q8_0.** Note that cold prefill slows with depth: 70K tokens took about 24 minutes (49 tok/s), which is the reason to keep agent sessions short and the prompt prefix stable.

## Current recommendations (i9, summary of the 2026-10-06/07 testing)

| Topic | Setting | Evidence |
|---|---|---|
| Models | `Qwen3.6-35B-A3B-MTP-UD-Q6_K` for speed, `Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q6_K_P` for vision/uncensored; nothing else | quality rounds, agent round (HauhauCS 73%, MTP 65-75%, within noise) |
| Speculation | MTP mode runs `suffix` + `mtp:n_max=1` (default); other `n_max` values and `ngram-mod` lose | speculative sections above |
| HauhauCS speed | needs `IK_LLAMA_NO_MMPROJ=1` + `IK_LLAMA_SPEC=...` (no vision) for drafting; default keeps vision | server disables speculation when `--mmproj` is loaded |
| Reasoning | off (`-rea off`, hard-coded in `start.sh`); on only per known-failing task with `-rea on --reasoning-budget 2048` and `max_tokens` >= 8000 | reasoning round: 8-9x slower, no gain overall. A per-request switch while the server runs with reasoning off was not tested |
| KV cache | q8_0 | q4_0: no speed gain, battery 1 task lower |
| Sessions | keep context short, prefix stable (`CLAUDE_CODE_ATTRIBUTION_HEADER=0` is set by `claude-providers.sh`), use slot save/restore after restarts | cold prefill is 2 min at 13K and about 24 min at 70K tokens |
| Agents | OpenCode and Claude Code both work (Claude Code: 14-15/20 on the agent tasks); expect about 25% run-to-run flips per task | agent round |
| Not usable on this CPU | dense 27B-class models (3.8 t/s), Kolibri-1 (engine support missing) | llama-bench, load test |

Hardware context (estimates, not measured here): decode on this CPU is about 70% of its memory-bandwidth ceiling, so tuning has little left; prompt processing (about 100-120 t/s) is the weak point. A Strix Halo mini PC or Apple M4 Pro would be roughly 2-3x faster on decode and 5x on prompt processing, a used 24 GB GPU more.
