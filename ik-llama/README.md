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
| `update-probook.sh` | Download/update ik_llama.cpp Windows binary |
| `update-i9.sh` | Download/update ik_llama.cpp Linux binary |
| `download-models-probook.sh` | Download GGUF models to `/mnt/c/data/llm/models` |
| `download-models-i9.sh` | Download GGUF models to `/data/llm/models` |
| `start-probook.sh <mode>` | Start llama-server on ProBook (runs from WSL2) |
| `start-i9.sh <mode>` | Start llama-server on i9 |
| `bench-i9.sh <mode>` | Benchmark i9 CPU thread settings with llama-bench |
| `bench-probook.sh <mode>` | Benchmark ProBook CPU thread settings with Windows llama-bench.exe |
| `setup-opencode-probook.sh` | Auto-generate OpenCode provider config from start script |
| `setup-opencode-i9.sh` | Auto-generate OpenCode provider config from start script |
| `tune-i9.sh` | OS-level tuning for inference (cpu governor, THP, NUMA) |

### Quick start — ProBook

```bash
./update-probook.sh
./download-models-probook.sh
./setup-opencode-probook.sh
./start-probook.sh qwen36u35b   # or: gemma qwen3coder glm47flash
```

Benchmark thread settings:

```bash
./bench-probook.sh qwen36u35b
./bench-probook.sh all
BENCH_THREADS="8 12 16" BENCH_THREADS_BATCH="8 12 16" ./bench-probook.sh qwen36u35b
```

### Quick start — i9

```bash
sudo ./tune-i9.sh       # OS tuning (once per boot)
./update-i9.sh
./download-models-i9.sh
./setup-opencode-i9.sh
./start-i9.sh qwen3coder   # or: qwen3fast qwen36u27b qwen36u35b gemma4 supergemma4 glm47flash
```

Benchmark thread settings:

```bash
./bench-i9.sh qwen3coder
./bench-i9.sh all
BENCH_THREADS="6 8 10" BENCH_THREADS_BATCH="24 32" ./bench-i9.sh qwen3coder
```

To compare results, start with the generated `*-summary.tsv`, then inspect the referenced CSV files. Look for the highest prompt processing throughput (`pp`/prompt tok/s) that does not hurt generation throughput (`tg`/generation tok/s). For OpenCode, prefer the best overall balance over the absolute highest prompt-only score.

Summarize benchmark CSVs:

```bash
./summarize-bench.py bench-results/*-summary.tsv
```

## Models

### ProBook (32 GB RAM)

| Mode | Model | Size | Context | Notes |
|---|---|---|---|---|
| `qwen36u35b` | Qwen3.6-35B-A3B-Uncensored IQ4\_NL | ~16 GB | 32 K | 35B MoE, 3B active |
| `gemma` | Gemma4-26B-A4B IQ4\_NL | ~13 GB | 64 K | 26B MoE, 4B active |
| `qwen3coder` | Qwen3-Coder-30B-A3B Q3\_K\_M | ~14 GB | 64 K | 30B MoE, 3B active |
| `glm47flash` | GLM-4.7-Flash Q4\_K\_M | ~17 GB | 32 K | 30B MoE, 3B active, DeepSeek-V2 MLA |

### i9 (64 GB RAM)

| Mode | Model | Size | Context | Notes |
|---|---|---|---|---|
| `qwen3coder` | Qwen3-Coder-30B-A3B-Instruct Q4\_K\_M | ~19 GB | 64 K | Main coding/docs model, 3B active |
| `qwen3fast` | Qwen3-14B Q5\_K\_M | ~10 GB | 32 K | Fast dense fallback for routine edits/docs |
| `qwen36u27b` | Qwen3.6-27B-Uncensored Q5\_K\_P | ~20 GB | 64 K | 27B dense — all params active |
| `qwen36u35b` | Qwen3.6-35B-A3B-Uncensored Q4\_K\_P | ~21 GB | 64 K | 35B MoE, 3B active |
| `gemma4` | Gemma4-26B-A4B Q5\_K\_M | ~21 GB | 128 K | 26B MoE, 4B active |
| `supergemma4` | SuperGemma4-26B-Uncensored Q4\_K\_M | ~17 GB | 128 K | Uncensored Gemma4 fine-tune |
| `glm47flash` | GLM-4.7-Flash Q5\_K\_M | ~20 GB | 64 K | 30B MoE, 3B active, coding-focused |

GLM-4.7-Flash uses the DeepSeek-V2 MLA attention architecture which is more efficient per active parameter and outperforms standard MoE attention at the same active-param count. It scores ~59% on SWE-Bench Verified.

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
| `--threads` | 8 | Generation threads (P-cores only). Override: `IK_LLAMA_THREADS` |
| `--threads-batch` | 24 | Prompt processing threads. Override: `IK_LLAMA_THREADS_BATCH` |
| `--ctx-size` | 32768–131072 | Context window |
| `-sps 0.5` | 0.5 | Slot prompt similarity for cache reuse |
| `-cram <MB>` | 8192–32768 | KV cache RAM limit |
| `-crs 0.5` | 0.5 | Cache similarity threshold |
| `-ctk q8_0` | q8_0 | Quantize K cache (requires flash attention) |
| `-ctv q8_0` | q8_0 | Quantize V cache (requires flash attention) |
| `-dt 0.1` | 0.1 | Defragmentation threshold |
| `--host 0.0.0.0` | — | Listen on all interfaces (required for WSL2) |
| `--jinja` | — | Enable Jinja templates (required for tool calling) |
| `-rea off` | off | Disable thinking/reasoning mode |
| `-v` | — | Verbose output (shows tok/s, timing) |
| `--mlock` | — | Lock model in RAM (i9 only, prevents swapping) |

### Qwen3 YaRN (context extension)

```
--rope-scaling yarn --yarn-orig-ctx 32768 --yarn-beta-fast 32 --yarn-beta-slow 1
```

Applied to Qwen3-family models when using contexts beyond 32K.

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

### ProBook (Ryzen 7 250, Zen 5, AVX512)

- Prompt eval: ~44 tok/s
- Generation: ~7 tok/s
- First message with long system prompt: ~5 min (cache cold)
- Subsequent messages: ~2.5 s (cache hit)

### i9-13900 (Raptor Lake, AVX2)

- Prompt eval: ~40–50 tok/s
- Generation: ~8–10 tok/s

### i9 speed notes

The i9 is CPU-only and AVX2-only, so dense 20 GB-class models are mostly memory-bandwidth bound. `qwen36u27b` is the highest-quality local option here, but it is not the fastest. For interactive coding latency, try these before changing infrastructure:

- Prefer `qwen3coder` for coding/docs work and `qwen3fast` when responsiveness matters more than max quality.
- Keep context as low as the task allows; 64K/128K context improves long sessions but slows prompt processing and grows KV memory.
- Keep `qwen3coder` at 64K for OpenCode sessions that quickly fill context; use `qwen3fast` when you can trade context and quality for responsiveness.
- Sweep generation threads instead of assuming more is better: `IK_LLAMA_THREADS=6`, `8`, `10`, and `12` are worth testing on the i9.
- Sweep prompt threads separately with `IK_LLAMA_THREADS_BATCH=24` and `32`; this mostly affects cold prompts and large context ingestion.
- If latency is still poor, add a smaller dense coding model tier (for example 14B-ish Q4/Q5) for routine edits and keep the 27B dense model for harder tasks.

## Key lessons

1. **`-ngl 0` always** — integrated GPU causes Vulkan OOM crashes
2. **Quantized KV cache requires flash attention on** — `-ctv q8_0` is incompatible with `--flash-attn off`; ik_llama.cpp enables FA by default which is correct
3. **Avoid `_XL` variants** — incompatible quantization format with ik_llama.cpp
4. **ProBook: use generic AVX512 build** — `znver5` crashes with MoE models
5. **i9 has no AVX512** — despite being 13th gen Raptor Lake; use AVX2 build only
6. **Prompt cache is critical** — first message is slow; subsequent messages hit cache and are fast
7. **`-rea off`** — disables thinking mode; cuts response time 50–80% for coding tasks
8. **MoE active-parameter ceiling** — 3B active params is the real intelligence limit regardless of quantization level; for more intelligence use a dense model like `qwen36u27b`
9. **GLM-4.7-Flash > Qwen3-Coder** at the same active-param count due to MLA attention architecture
