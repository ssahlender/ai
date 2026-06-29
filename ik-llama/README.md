# ik_llama.cpp scripts

CPU-only local LLM inference on two machines using [ik_llama.cpp](https://github.com/Thireus/ik_llama.cpp) — a fork of llama.cpp with better AVX512/AVX2 kernels, optimized quantization formats (IQ\*, K\_P variants), and improved MoE scheduling.

## Hardware

| Machine | CPU | RAM | OS | Notes |
|---|---|---|---|---|
| HP ProBook (Ryzen) | AMD Ryzen 7 250 (Zen 5) | 32 GB | Windows 11 + WSL2 | AVX512 VNNI VBMI BF16 |
| Work PC (i9) | Intel Core i9-13900 (Raptor Lake) | 64 GB | Debian 13 | AVX2 only — no AVX512 |

Neither machine has a usable GPU. The ProBook's integrated AMD Radeon causes Vulkan OOM crashes — always use `-ngl 0`.

## Scripts

| Script | Purpose |
|---|---|
| `update.sh <machine>` | Download/update ik_llama.cpp (Linux/Windows) or brew upgrade llama.cpp (Mac) |
| `download-models.sh <machine>` | Download GGUF + mmproj files for i9/probook/macbook-air |
| `start.sh <machine> <mode>` | Start llama-server on any machine |
| `setup-agents.sh <machine>` | Auto-generate OpenCode/Pi provider config (parses start.sh) |
| `claude-providers.sh [provider] [model]` | Interactive picker & launch Claude Code with local or remote models (shows live n_ctx from `/props`) |
| `.secrets.example` | Template for `~/.secrets` (copy, chmod 600, fill in keys) |
| `ocg-proxy.py` | Anthropic ↔ OpenAI proxy for OpenCode Go (DeepSeek/Kimi/GLM + Claude Code) |
| `bench.sh <machine> <mode>` | Benchmark CPU thread settings with llama-bench (i9/probook) |
| `model-info.sh` | Show on-disk models, file sizes, mmproj status |
| `cleanup-models.sh <machine>` | Remove GGUFs not in active start.sh lineup — whitelist-driven, dry-run by default |
| `tune-i9.sh` | OS-level tuning for inference (cpu governor, THP, NUMA) |

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

### Quick start — ProBook

```bash
./update.sh probook
./download-models.sh probook
./setup-agents.sh probook
./start.sh probook qwen36u35b   # or: ornith35q4km
```

Benchmark thread settings:

```bash
./bench.sh probook qwen36u35b
./bench.sh probook all
BENCH_THREADS="8 12 16" BENCH_THREADS_BATCH="8 12 16" ./bench.sh probook qwen36u35b
./summarize-bench.py bench-results/*-summary.tsv
```

> **ProBook bench quirks:** runs bench.sh one model at a time (`probook qwen36u35b` then `probook ornith35q4km`), not `all` at once — switching models mid-batch exhausts the Windows standby page list and causes mmap exit 5. The script clears the standby list automatically before each run now, but running models back-to-back in a single `all` invocation is still fragile on 32 GB.

### Quick start — i9

```bash
sudo ./tune-i9.sh       # OS tuning (once per boot)
./update.sh i9
./download-models.sh i9
./setup-agents.sh i9
./start.sh i9 qwopus35bq5km   # or: qwen36u35bq6kp ornith35q6k supergemma4q4km qwen3codernext
./cleanup-models.sh i9     # dry-run obsolete GGUF cleanup
```

All i9 start modes default to `IK_LLAMA_THREADS=8` and `IK_LLAMA_THREADS_BATCH=24`. Override these only for explicit benchmark tests.

### Quick start — MacBook Air M4

```bash
brew install llama.cpp             # prerequisite (once)
./download-models.sh macbook-air
./setup-agents.sh macbook-air
./start.sh macbook-air qwen36u27b  # daily: 27B dense IQ4_XS, 32K ctx
./start.sh macbook-air qwen36u35b  # fallback: 35B MoE IQ4_NL, 16K ctx
```

All Mac modes use Metal GPU (`-ngl 99`) with 4 threads. Same HF repos and mmproj as i9.

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
|---|---|---|---|---|---|---|
| `qwen36u35b` | Qwen3.6-35B-A3B-Uncensored IQ4\_NL | ~16 GB | 32 K | no | 35B MoE, 3B active |
| `ornith35q4km` | Ornith-1.0 35B-A3B Q4\_K\_M | ~21 GB | 64 K | no | RL agentic coder, Qwen3 MoE base, MIT |

### MacBook Air M4 (24 GB, Metal GPU)

| Mode | Model | Size | Context | Vision | Notes |
|---|---|---|---|---|---|
| `qwen36u27b` | Qwen3.6-27B-Uncensored IQ4\_XS | ~15 GB | 32 K | yes | 27B dense — all params active, daily driver |
| `qwen36u35b` | Qwen3.6-35B-A3B-Uncensored IQ4\_NL | ~16 GB | 16 K | yes | 35B MoE, 3B active — speed fallback |

Quick start:
```bash
brew install llama.cpp                      # prerequisite
./download-models.sh macbook-air             # pull GGUFs + mmproj
./setup-agents.sh macbook-air                # wire OpenCode + Pi
./start.sh macbook-air qwen36u27b            # daily driver: 27B dense, 32K ctx
```

The 27B dense IQ4\_XS is the smarter pick — all 27B params active vs 3B MoE for the 35B, and still fits at 32K context on 24 GB unified memory. Same HF repos and mmproj files as i9, just different quants (IQ4\_XS/IQ4\_NL for Mac vs K\_P for i9).

### i9 (64 GB RAM)

| Mode | Model | Size | Context | Vision | Notes |
|---|---|---|---|---|---|---|
| `qwen36u35bq6kp` | Qwen3.6-35B-A3B-Uncensored Q6\_K\_P | ~31 GB | 128 K | yes | 35B MoE quality baseline + vision |
| `qwopus35bq5km` | Qwopus3.6-35B-A3B Q5\_K\_M | ~25 GB | 128 K | yes | Daily driver — fastest, reasoning, vision |
| `ornith35q6k` | Ornith-1.0 35B-A3B Q6\_K | ~29 GB | 128 K | no | RL agentic coder, Qwen3 MoE base, MIT |
| `supergemma4q4km` | SuperGemma4-26B-Uncensored Q4\_K\_M | ~17 GB | 128 K | no | Uncensored fallback, text-only |
| `qwen3codernext` | Qwen3-Coder-Next 80B-A3B UD-Q3\_K\_M | ~36 GB | 128 K | no | 80B MoE, 3B active — heavy coder test |

GLM-4.7-Flash uses the DeepSeek-V2 MLA attention architecture and remains a useful comparison model, but measured slower than the Qwen MoE models on this i9. It scores ~59% on SWE-Bench Verified.

Qwen3-Coder-Next 80B-A3B (UD-Q3_K_M, ~36 GB) runs at ~98 pp tok/s and ~16 tg tok/s at 8/24 — about 20% slower than Qwopus due to the larger model footprint (same 3B active params, more bytes to stream). Context bumped to 128K (from 65K) so `/compact` fits long sessions; KV capped at 24 GB via `cram`. Still interactive; quality check pending.

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
| `IK_LLAMA_CRAM_MB` | env override | Override the per-model KV cache RAM limit |
| `-sps 0.5` | 0.5 | Slot prompt similarity for cache reuse |
| `-cram <MB>` | 8192–32768 | KV cache RAM limit |
| `-crs 0.5` | 0.5 | Cache similarity threshold |
| `-ctk q8_0` | q8_0 | Quantize K cache (requires flash attention) |
| `-ctv q8_0` | q8_0 | Quantize V cache (requires flash attention) |
| `-dt 0.1` | 0.1 | Defragmentation threshold |
| `--host 0.0.0.0` | — | Listen on all interfaces (required for WSL2) |
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

## OS tuning (i9)

Run `sudo ./tune-i9.sh` once per boot to apply:

- **CPU governor → performance** — prevents frequency scaling latency on the single-token generation path
- **Transparent Huge Pages → madvise** — lets llama-server opt into 2MB pages without wasting them on other processes
- **NUMA balancing → off** — no benefit on single-socket; avoids kernel migration overhead

All changes revert on reboot. The script is idempotent — safe to re-run.

## Performance

### ProBook (Ryzen 7 250, Zen 5, AVX512, Windows 11 + WSL2)

Benchmarked with `p=2048 n=128 r=3` via llama-bench.exe (x64 AVX512 VNNI VBMI BF16 build):

| Mode | Threads (gen/batch) | pp2048 (t/s) | tg128 (t/s) |
|---|---|---:|---:|
| `qwen36u35b` IQ4\_NL | **8 / 8** | **109.6** | 12.9 |
| `qwen36u35b` IQ4\_NL | 12 / 12 | 100.2 | **13.9** |
| `qwen36u35b` IQ4\_NL | 8 / 16 | 95.0 | 12.9 |
| `qwen36u35b` IQ4\_NL | 16 / 8 | 85.1 | 11.7 |
| `ornith35q4km` Q4\_K\_M | 12 / 16 | **106.6** | **13.2** |
| `ornith35q4km` Q4\_K\_M | 8 / 16 | 105.2 | 13.2 |
| `ornith35q4km` Q4\_K\_M | 8 / 8 | 100.0 | 13.3 |

Default startup uses `THREADS=8 THREADS_BATCH=16` — a balanced setting for both models (qwen pp≈95, ornith pp≈105). Use `IK_LLAMA_THREADS=8 IK_LLAMA_THREADS_BATCH=8` for maximum qwen prompt throughput.

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
| `qwen36u35bq6kp` | ~122.8 | ~22.6 | Quality baseline |
| `ornith35q6k` | 122.5 | 23.1 | Agentic coder |
| `supergemma4q4km` | ~129 | ~23 | Uncensored fallback |
| `qwen3codernext` | ~98 | ~16 | 80B MoE heavy coder |

Qwopus Q5_K_M is the clear daily driver — fastest on both pp and tg. Ornith Q6_K matches Qwen3.6 Q6_K_P on throughput and is the dedicated coding slot. All three are well above the interactive threshold for OpenCode tool loops.

### i9 speed notes

The i9 is CPU-only and AVX2-only, so dense 20 GB-class models are mostly memory-bandwidth bound. `qwen36u27bq5kp` is the retained dense quality option, but it is not interactive. Qwen3.6-35B-A3B Q4/Q5/Q8 HauhauCS quants are replaced by Qwopus3.6-35B-A3B Q5_K_M and Q6_K. Qwen3-Coder A3B failed manual quality even at Q8.

- Test `qwopus35bq5km` first for daily use. Keep `qwopus35bq6k` and `qwen36u35bq6kp` for quality checks.
- Keep context as low as the task allows; 64K/128K context improves long sessions but slows prompt processing and grows KV memory.
- Use `IK_LLAMA_THREADS=8` and `IK_LLAMA_THREADS_BATCH=24` as the default i9 startup point.
- Avoid `IK_LLAMA_THREADS=10` and `12`; benchmarks were consistently worse than `6` and `8`.
- Keep `qwen36u27bq5kp` for quality checks only. It is too slow for normal OpenCode loops.

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

**ornith35q4km (Q4\_K\_M, 20 GB):**

| gen/batch | pp2048 (t/s) | tg128 (t/s) |
|---|---:|---:|
| 12 / 16 | **106.6** | **13.2** |
| 8 / 16 | 105.2 | 13.2 |
| 16 / 16 | 104.4 | 12.1 |
| 16 / 12 | 104.1 | 12.1 |
| 12 / 8 | 103.2 | 12.4 |
| 16 / 8 | 102.9 | 12.1 |
| 12 / 12 | 102.8 | 12.9 |
| 8 / 12 | 102.4 | 12.6 |
| 8 / 8 | 100.0 | 13.3 |

Default `8/16` is the best balanced setting for both models. Use `8/8` (`IK_LLAMA_THREADS=8 IK_LLAMA_THREADS_BATCH=8`) only if qwen prompt throughput is the priority.

### Completed i9 benchmark notes

`8/24` is the best default. `8/32` drops pp significantly with no tg gain.

**Active models — best rows at `8/24`:**

| Mode | pp2048 (t/s) | tg128 (t/s) | Notes |
|---|---:|---:|---|
| `qwopus35bq5km` | **130.9** | **26.4** | Daily driver |
| `supergemma4q4km` | 129.1 | 23.2 | Uncensored fallback |
| `qwen36u35bq6kp` | 122.8 | 22.6 | Quality baseline + vision |
| `ornith35q6k` | 122.5 | 23.1 | Agentic coder |
| `qwen3codernext` | 92.7 | 16.3 | 80B MoE heavy coder |

**Rejected candidates (historical):**

| Mode | pp2048 (t/s) | tg128 (t/s) | Reason dropped |
|---|---:|---:|---|
| `qwen3coderq5km` | 110.6 | 29.8 | Failed manual quality |
| `qwen3coderq8` | 105.8 | 20.7 | Failed manual quality |
| `qwen3coderq6k` | 102.1 | 25.6 | Failed manual quality |
| `glm47flashq5km` | 91.7 | 20.8 | Slower than Qwen MoE, low quality |
| `qwen3fast:q4/q5` | ~33–40 | ~6–7 | Too slow |
| `qwen38b:q4/q5` | ~60 | ~13 | Not competitive with MoE |
| `qwen332b / qwen25coder32b` | ~14 | ~3 | Way too slow on AVX2 |
| `qwen36u27bq5kp` | 17.8 | 3.4 | Dense 27B — quality only, not interactive |

The benchmark script accepts explicit quantized presets like `qwopus35b:q5km`. The active benchmark set is `qwen36u35bq6kp`, `qwopus35bq5km`, `ornith35q6k`, `supergemma4q4km`, and `qwen3codernext`.

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
5. **i9 has no AVX512** — despite being 13th gen Raptor Lake; use AVX2 build only
6. **Prompt cache is critical** — first message is slow; subsequent messages hit cache and are fast
7. **`-rea off`** — disables thinking mode; cuts response time 50–80% for coding tasks
8. **MoE active-parameter ceiling** — 3B active params is the real intelligence limit regardless of quantization level; for more intelligence use a dense model like `qwen36u27bq5kp`
9. **GLM-4.7-Flash is not faster than Qwen3-Coder on this i9** — despite MLA, measured throughput was lower than the Qwen MoE models
10. **Vision requires mmproj** — Qwen3.6, Qwopus3.6, and Gemma4 models support image input when `--mmproj <file>.gguf` is passed to llama-server. The mmproj file is downloaded alongside the model GGUF. SuperGemma4 and GLM-4.7-Flash are text-only.
11. **One server slot per active agent** — `--parallel 2` divides the configured context between slots, while unrelated sessions evict each other's cached prefixes. Keep the default `IK_LLAMA_PARALLEL=1`; use separate server instances when concurrent agents need full context and stable cache reuse.
12. **No YARN for Qwen3 instruct models** — Qwen3 instruct supports 128K context natively. YARN (`--rope-scaling yarn --yarn-orig-ctx 32768`) was a Qwen2.5-era workaround for 32K base models. On Qwen3 it is redundant and, critically, causes ik_llama to silently disable context shift, causing hard 500 errors when the context fills. All Qwen3-family modes have YARN removed.
13. **`--context-shift on` is explicit** — context shift is on by default in llama.cpp/ik_llama but YARN overrides it internally. Now set explicitly in `start_model()` as a belt-and-suspenders guard against version differences. With context shift on, a full KV cache softly rolls out old tokens instead of returning a 500 error — essential for long sessions and `/compact` requests.
14. **Claude Code does not auto-compact for local models** — Claude Code reads `context_window` from the Anthropic SDK's `data[].context_window` field in the `/v1/models` response. ik_llama returns this in a non-standard `models[]` extension array instead, so Claude Code falls back to `n_ctx_train` (262K for Qwen3-Coder-Next) as the effective window and will not auto-compact until the session is enormous. Use `/compact` manually before sessions grow too large, or restart the server with a larger context.
15. **ProBook: `bench.sh` uses JSON output, not CSV** — `llama-bench.exe` embeds a null byte in the `cpu_info` CSV field, which silently truncates every data row (no performance numbers captured). `-o json` is used instead. `summarize-bench.py` reads both formats.
16. **ProBook: never run `strings` on a Windows PE binary from WSL2** — reading a `.exe` or `.dll` via Linux file APIs invalidates the Windows page-cache state for that file, causing subsequent `mmap` calls by Windows processes to fail with `ERROR_ACCESS_DENIED` (exit 5). `bench.sh` previously used `strings "$BENCH"` to detect flags; this is removed. `-h` output alone is sufficient.
17. **ProBook: clear Windows standby page list between benchmark runs** — after each ~20 GB model run, Windows retains model pages in the standby list. Switching to a different model before the standby list is evicted causes mmap to fail with exit 5. `bench.sh` calls `NtSetSystemInformation(80, ...)` via PowerShell before each run to drain the standby list.

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
