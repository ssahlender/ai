# ik_llama.cpp scripts

CPU-only local LLM inference using [ik_llama.cpp](https://github.com/ikawrakow/ik_llama.cpp) (authored by Iwan Kawrakow, packaged by [Thireus](https://github.com/Thireus/ik_llama.cpp)) — an optimized fork of llama.cpp featuring custom AVX2/AVX-512 GEMM tiling, optimized quantization formats (IQ\*, K\_P variants), and specialized MoE matrix scheduling.

## Hardware

| Machine | CPU | RAM | OS | Notes |
|---|---|---|---|---|
| HP ProBook (Ryzen) | AMD Ryzen 7 250 (Zen 5) | 32 GB | Windows 11 (native) | AVX512 VNNI VBMI BF16 |
| Work PC (i9) | Intel Core i9-13900 (Raptor Lake) | 64 GB | Debian 12 (bookworm), GLIBC 2.36 | AVX2 + AVX-VNNI — no AVX512 |

Neither machine has a usable GPU. The ProBook's integrated AMD Radeon causes Vulkan OOM crashes — always use `-ngl 0`.

## Scripts

| Script | Purpose |
|---|---|
| `update.sh <machine>` | Download/update ik_llama.cpp (i9) or brew upgrade llama.cpp (macbook-air) |
| `download-models.sh <machine>` | Download GGUF + mmproj files for i9/macbook-air |
| `start.sh <machine> <mode>` | Start llama-server on i9 or macbook-air |
| `setup-agents.sh <machine>` | Auto-generate OpenCode/Pi provider config (parses start.sh) |
| `claude-providers.sh [provider] [model]` | Interactive picker & launch Claude Code with local or remote models (shows live n_ctx from `/props`) |
| `.secrets.example` | Template for `~/.secrets` (copy, chmod 600, fill in keys) |
| `ocg-proxy.py` | Anthropic ↔ OpenAI proxy for OpenCode Go (DeepSeek/Kimi/GLM + Claude Code) |
| `bench.sh <machine> <mode>` | Benchmark CPU thread settings with llama-bench (i9) |
| `model-info.sh` | Show on-disk models, file sizes, mmproj status |
| `cleanup-models.sh <machine>` | Remove GGUFs not in active start.sh lineup — whitelist-driven, dry-run by default |

`setup-agents.sh` writes the `ik-llama` provider for OpenCode when `opencode` is
installed and for Pi when `pi` is installed. Per-model context values are parsed
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
IK_LLAMA_CTX_SIZE=32768 ./start.sh i9 qwopus35bq5km
```

Use `OPENCODE_OUTPUT_LIMIT=<tokens>` only to change OpenCode's reserved output
budget for context accounting. Use `OPENCODE_COMPACTION_RESERVED=<tokens>` only
when testing a different compaction buffer.

Pi config is written to `~/.pi/agent/models.json` with `api:
"openai-completions"`, `contextWindow`, and `maxTokens` for each local model.

### Quick start — ProBook (Native Windows PowerShell)

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

### Quick start — i9

```bash
./update.sh i9
./download-models.sh i9
./setup-agents.sh i9
./start.sh i9 qwopus35bq5km   # or: qwen36u35bq6kp supergemma4q4km qwen3codernext
./cleanup-models.sh i9     # dry-run obsolete GGUF cleanup
```

All i9 start modes default to `IK_LLAMA_THREADS=8` and `IK_LLAMA_THREADS_BATCH=24`. Override these only for explicit benchmark tests.

### Quick start — MacBook Air M4

```bash
brew install llama.cpp             # prerequisite (once)
./download-models.sh macbook-air
./setup-agents.sh macbook-air
./start.sh macbook-air qwen36u27b   # daily: 27B dense IQ4_XS, 32K ctx
./start.sh macbook-air qwen36u35b   # general: 35B MoE IQ4_NL, 16K ctx
./start.sh macbook-air qwen3coder30b  # coding: 30B MoE IQ4_NL, 32K ctx
```

All Mac modes use Metal GPU (`-ngl 99`) with 4 threads. Same HF repos and mmproj as i9.

> **The Mac's daily driver is Ollama, not this path** — see `../ollama/README.md`.
> This GGUF/Metal path is the alternative. Its Mac lineup predates the memory
> ceiling measured on that machine (a 17.6 GB model OOM'd at 8K context; the
> guard aborts at 16.9 GB), so if you use it there, prefer `IQ3_M` (14.38 GiB)
> or `Q2_K_P` (13.95 GiB) from the same repo — both recorded with sizes and
> hashes in `../llm/MODELS.md`.

For OpenCode edit loops where "Preparing write" feels slow, first try the same coder
model with a smaller active context:

```bash
IK_LLAMA_CTX_SIZE=32768 ./start.sh i9 qwopus35bq5km
```

Use the normal 64K default again when the session really needs the extra context.

Benchmark thread settings:

```bash
./bench.sh i9 qwopus35bq5km
./bench.sh i9 all
./bench.sh i9 qwen36
BENCH_THREADS="6 8" BENCH_THREADS_BATCH="24 32" ./bench.sh i9 qwopus35bq5km
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
| `qwen36u27b` | Qwen3.6-27B-Uncensored IQ4\_XS | ~15 GB | 32 K | yes | 27B dense — all params active, daily driver |
| `qwen36u35b` | Qwen3.6-35B-A3B-Uncensored IQ4\_NL | ~16 GB | 16 K | yes | 35B MoE, 3B active — general + vision |
| `qwen3coder30b` | Qwen3-Coder-30B-A3B IQ4\_NL | ~17 GB | 32 K | no | Dedicated agentic coder, 262K native ctx |

Quick start:
```bash
brew install llama.cpp                      # prerequisite
./download-models.sh macbook-air             # pull GGUFs + mmproj
./setup-agents.sh macbook-air                # wire OpenCode + Pi
./start.sh macbook-air qwen36u27b            # daily driver: 27B dense, 32K ctx
```

The 27B dense IQ4\_XS is the smarter general pick — all 27B params active vs 3B MoE for the 35B, and still fits at 32K context on 24 GB unified memory. Use `qwen3coder30b` for focused coding sessions. Same HF repos and mmproj files as i9, just different quants (IQ4\_XS/IQ4\_NL for Mac vs K\_P for i9).

### i9 (64 GB RAM)

| Mode | Model | Size | Context | Vision | Notes |
|---|---|---|---|---|---|
| `qwen36u35bq6kp` | Qwen3.6-35B-A3B-Uncensored Q6\_K\_P | ~31 GB | 128 K | yes | 35B MoE quality baseline + vision |
| `qwopus35bq5km` | Qwopus3.6-35B-A3B Q5\_K\_M | ~25 GB | 128 K | yes | Daily driver — fastest, reasoning, vision |
| `supergemma4q4km` | SuperGemma4-26B-Uncensored Q4\_K\_M | ~17 GB | 128 K | no | Uncensored fallback, text-only |
| `qwen3codernext` | Qwen3-Coder-Next 80B-A3B UD-Q3\_K\_M | ~36 GB | 128 K | no | 80B MoE, 3B active — heavy coder test |
| `qwen36u27bq5kp` | Qwen3.6-27B-Uncensored Q5\_K\_P (dense) | ~19 GB | 128 K | no | Dense, all 27B active — slow (3.4 tg tok/s measured) but higher quality ceiling than 3B-active MoE; kept on hand since no GPU upgrade is coming |

Qwen3-Coder-Next 80B-A3B (UD-Q3_K_M, ~36 GB) runs at ~98 pp tok/s and ~16 tg tok/s at 8/24 — about 20% slower than Qwopus due to the larger model footprint (same 3B active params, more bytes to stream). Context set to 128K for long agent sessions; prompt-cache RAM capped via `cram`.

NVIDIA's Nemotron-3.5-Lightning-30B-A3B was tried and dropped: its architecture interleaves Mamba-2 (SSM) layers with MoE and attention layers, which ik_llama.cpp (an AVX2/quant-kernel-focused `llama.cpp` fork) doesn't implement — it fails to load with `unknown model architecture: 'nemotron_h_moe'`. Confirmed via direct load test, not just a version mismatch.

**`-ub`/`--ubatch-size` default raised to 1024** (`IK_LLAMA_UBATCH` env override) after a sweep on `qwopus35bq5km` showed a free ~2.5% pp gain (135.8 → 139.1 t/s at ub=1024 vs the previous default of 512) with `tg` unaffected. No GPU-style cliff at small ubatch values on this AVX2 CPU path, unlike reports on GPU/ROCm backends.

## Binaries

Downloaded automatically by `update-*.sh`. Correct build for each machine:

| Machine | Build pattern |
|---|---|
| ProBook (Windows) | `*-bin-win-cpu-x64-avx512_vnni_vbmi_bf16.zip` |
| i9 (Linux) | `*-bin-ubuntu-x64-avx2.zip` |

Note: Use the generic `avx512_vnni_vbmi_bf16` build on ProBook, **not** `znver5` — the znver5 build crashes with Qwen3 MoE models.

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
| `--mmproj <file>` | — | Multimodal projector GGUF for vision (Qwen3.6, Qwopus3.6, Gemma4) |

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

Prompt processing is close (~80% of i9) thanks to AVX512. Token generation is roughly half — memory bandwidth limited by 32 GB laptop DDR5 vs 64 GB desktop DDR5.

- First message with long system prompt: ~5–10 s (cache cold, mmap)
- Subsequent messages: ~2–3 s (cache hit)

### i9-13900 (Raptor Lake, AVX2)

Active model throughput at the default `8/24` thread setting:

| Mode | pp2048 (t/s) | tg128 (t/s) | Notes |
|---|---:|---:|---|
| `qwopus35bq5km` | **130.9** | **26.4** | Daily driver |
| `supergemma4q4km` | ~129 | ~23 | Uncensored fallback |
| `qwen36u35bq6kp` | ~122.8 | ~22.6 | Quality baseline + vision |
| `qwen3codernext` | ~98 | ~16 | 80B MoE heavy coder |

Qwopus Q5_K_M is the clear daily driver — fastest on both pp and tg. All models are well above the interactive threshold for OpenCode tool loops.

### i9 speed notes

The i9 is CPU-only and AVX2-only, so dense 20 GB-class models are mostly memory-bandwidth bound. Qwen3-Coder-Next 80B-A3B covers the heavy coding slot; Qwopus covers daily use. Ornith-1.0 35B failed manual quality check and is removed.

- Test `qwopus35bq5km` first for daily use.
- Keep context as low as the task allows; 64K/128K context improves long sessions but slows prompt processing and grows KV memory.
- Use `IK_LLAMA_THREADS=8` and `IK_LLAMA_THREADS_BATCH=24` as the default i9 startup point.
- Avoid `IK_LLAMA_THREADS=10` and `12`; benchmarks were consistently worse than `6` and `8`.

### ik_llama.cpp vs standard llama.cpp (i9, qwen3codernext, b9789)

Measured on the same model (Qwen3-Coder-Next UD-Q3\_K\_M) with `p=2048 n=128 r=3`:

| Engine | Threads | pp2048 (t/s) | tg128 (t/s) |
|---|---|---:|---:|
| ik_llama.cpp (Thireus fork) | 8 gen / 24 batch | **98.6** | 15.8 |
| standard llama.cpp b9789 | 8 | 45.4 | 15.8 |
| ik_llama.cpp | 16 gen / 24 batch | 93.1 | 14.2 |
| standard llama.cpp b9789 | 16 | 46.4 | 14.7 |

**Prompt processing: ik_llama is ~2.1× faster.** Token generation is identical (both are memory-bandwidth bound). Standard llama.cpp b9789 correctly auto-detected the i9 as Alder Lake and loaded `libggml-cpu-alderlake.so`, so this is a fair comparison — not a configuration gap.

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

**qwen3coder30b (Q4\_K\_M, ~19 GB):** benchmarks pending — run via `llm/bench/bench-threads.ps1` after download.

Default `8/16` is the best balanced setting for qwen36u35b. Use `8/8` (`IK_LLAMA_THREADS=8 IK_LLAMA_THREADS_BATCH=8`) only if qwen prompt throughput is the priority.

### Completed i9 benchmark notes

`8/24` is the best default. `8/32` drops pp significantly with no tg gain.

**Active models — best rows at `8/24`:**

| Mode | pp2048 (t/s) | tg128 (t/s) | Notes |
|---|---:|---:|---|
| `qwopus35bq5km` | **130.9** | **26.4** | Daily driver |
| `supergemma4q4km` | 129.1 | 23.2 | Uncensored fallback |
| `qwen36u35bq6kp` | 122.8 | 22.6 | Quality baseline + vision |
| `qwen3codernext` | 92.7 | 16.3 | 80B MoE heavy coder |

**Rejected candidates (historical):**

| Mode | pp2048 (t/s) | tg128 (t/s) | Reason dropped |
|---|---:|---:|---|
| `ornith35q6k` | 122.5 | 23.1 | Good throughput, failed manual quality |
| `qwen3coderq5km` | 110.6 | 29.8 | Failed manual quality |
| `qwen3coderq8` | 105.8 | 20.7 | Failed manual quality |
| `qwen3coderq6k` | 102.1 | 25.6 | Failed manual quality |
| `glm47flashq5km` | 91.7 | 20.8 | Slower than Qwen MoE, low quality |
| `qwen3fast:q4/q5` | ~33–40 | ~6–7 | Too slow |
| `qwen38b:q4/q5` | ~60 | ~13 | Not competitive with MoE |
| `qwen332b / qwen25coder32b` | ~14 | ~3 | Way too slow on AVX2 |

The benchmark script accepts explicit quantized presets like `qwopus35b:q5km`. The active benchmark set is `qwen36u35bq6kp`, `qwopus35bq5km`, `supergemma4q4km`, and `qwen3codernext`.

**Benchmark output:** TSV summary files (`bench-results/*-summary.tsv`) are metadata indexes pointing to individual JSON files (one per thread combo). Use `summarize-bench.py` to get throughput numbers:

```bash
./summarize-bench.py bench-results/*-summary.tsv
```

For 128K OpenCode sessions on the i9 with `qwen36u35bq6kp`, start with:

```bash
./start.sh i9 qwen36u35bq6kp
OPENCODE_COMPACTION_RESERVED=24000 ./setup-agents.sh i9
```

To free disk space after rotating models:

```bash
./cleanup-models.sh i9        # dry run — shows what would be removed
./cleanup-models.sh i9 --apply
```

The cleanup script derives the whitelist from `start.sh` MODES automatically — any file not in the active lineup is flagged.

## Key lessons

1. **`-ngl 0` always** — integrated GPU causes Vulkan OOM crashes
2. **Quantized KV cache requires flash attention on** — `-ctv q8_0` is incompatible with `--flash-attn off`; ik_llama.cpp enables FA by default which is correct
3. **Avoid `_XL` variants** — incompatible quantization format with ik_llama.cpp
4. **ProBook: use generic AVX512 build** — `znver5` crashes with MoE models (exit code 29 on any model load, despite `-h` working)
5. **i9 has no AVX512** — Intel fused off AVX-512 on consumer Raptor Lake; use AVX2 + AVX-VNNI build only
6. **Prefill and prefix-cache stability are the true bottleneck on CPU** — decode speed (16–26 t/s) is negligible next to cold prefill at ~100 t/s (ingesting a 50K context cold takes >8 minutes; 128K takes >20 minutes). Practical turnaround in coding agents is dominated by prefix-cache hits (`--cache-reuse`, single slot `IK_LLAMA_PARALLEL=1`, stable system prompts, static tool definitions).
7. **128K context is an emergency ceiling, not routine operating depth** — operate at 16K–32K with agent-level harness compaction (e.g. OpenCode reserving 10,000 tokens to prune old tool outputs) rather than letting contexts inflate to 100K+.
8. **Hybrid linear attention in Qwen3-Coder-Next 80B-A3B** — combines Gated DeltaNet (linear recurrent layers) with only 12 full-attention layers. This provides $O(1)$ memory per linear layer at deep context, explaining why an 80B-class model runs in 64 GB RAM. Note that recurrent hidden state cannot be shifted by server-side context shift, making harness-side compaction strictly mandatory.
9. **Claude Code attribution header causes ~90% silent slowdown** — Claude Code inserts dynamic attribution metadata into request headers on every turn, altering the prompt prefix and forcing 100% cache misses on local servers. Adding `"CLAUDE_CODE_ATTRIBUTION_HEADER": "0"` in `~/.claude/settings.json` stabilizes the prefix.
10. **The "Empty Answer" thinking budget trap** — on reasoning models, small `max_tokens` budgets (e.g. 32 or 64) spend every token in `reasoning_content` and return empty `content: ""`. Appending `/no_think` does not suppress thinking on these templates. Either provide generous token headroom (1024+) or turn off internal thinking server-side via `-rea off` (which cuts turn latency 50–80% for coding).
11. **MoE active-parameter ceiling vs dense models** — 35B-A3B MoE routes ~3.2B active parameters per token. While fast on DDR5 (~24 t/s), dense 27B–32B models have full parameter depth on every token. For complex logic, speculative decoding (prompt lookup / n-gram drafting) on dense models can narrow the generation gap without model degradation.
12. **Vision requires mmproj** — Qwen3.6, Qwopus3.6, and Gemma4 models support image input when `--mmproj <file>.gguf` is passed to llama-server. The mmproj file is downloaded alongside the model GGUF. SuperGemma4 and GLM-4.7-Flash are text-only.
13. **One server slot per active agent** — `--parallel 2` divides the configured context between slots, while unrelated sessions evict each other's cached prefixes. Keep the default `IK_LLAMA_PARALLEL=1`; use separate server instances when concurrent agents need full context and stable cache reuse.
14. **No YARN for Qwen3 instruct models** — Qwen3 instruct supports 128K context natively. YARN (`--rope-scaling yarn --yarn-orig-ctx 32768`) was a Qwen2.5-era workaround for 32K base models. On Qwen3 it is redundant and silently disables context shift in ik_llama, causing hard 500 errors when context fills. All Qwen3-family modes have YARN removed.
15. **`--context-shift on` is explicit** — set explicitly in `start_model()` as a guard against version differences. Note that harness-side compaction should always be primary.
16. **ProBook: `bench.sh` uses JSON output, not CSV** — `llama-bench.exe` embeds a null byte in the `cpu_info` CSV field, which silently truncates every data row (no performance numbers captured). `-o json` is used instead. `summarize-bench.py` reads both formats.
17. **ProBook: native Windows execution** — WSL has been retired on ProBook. All model execution and benchmarks now run natively on Windows via PowerShell scripts in `llm/`.
18. **ProBook: clear Windows standby page list between benchmark runs** — after each ~20 GB model run, Windows retains model pages in the standby list. Switching to a different model before the standby list is evicted causes mmap to fail with exit 5. In native Windows benchmarks (`llm/bench/`), the standby list is cleared between runs.

## Debian 12 / GLIBC 2.36 compatibility

Homebrew binary bottles are built on Ubuntu 24.04 (GLIBC 2.38). They won't run
on Debian 12 (GLIBC 2.36). Affected: node, pi, and any brew formula that ships
a compiled binary.

**Symptoms:**
```
/home/linuxbrew/.linuxbrew/opt/node/bin/node: /lib/x86_64-linux-gnu/libm.so.6:
version `GLIBC_2.38' not found
```

**Fix — wrapper script (no root, no npm):**
`pi-install.sh` auto-detects the glibc issue and creates `~/.local/bin/pi`
— a wrapper that runs pi's JS via the system node, bypassing brew's broken
node. Brew still manages pi upgrades; the wrapper auto-picks the latest version.

For other brew formulae with the same issue, either build from source
(`brew install --build-from-source <formula>`) or install via the system package
manager instead of brew.

Ubuntu 24.04 and macOS are unaffected — brew bottles work natively.
