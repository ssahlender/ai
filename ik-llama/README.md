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
| `cleanup-models-i9.sh` | Remove rejected/obsolete i9 GGUF files (dry-run by default) |
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
./start-i9.sh qwen3coderq4   # or: qwen3coderq3 qwen36u27bq5kp qwen36u35bq4kp gemma4q5km supergemma4q4km glm47flashq5km
./cleanup-models-i9.sh     # dry-run obsolete GGUF cleanup
```

Benchmark thread settings:

```bash
./bench-i9.sh qwen3coderq4
./bench-i9.sh all
./bench-i9.sh tomorrow
./bench-i9.sh qwen3coderq3
BENCH_THREADS="6 8" BENCH_THREADS_BATCH="24 32" ./bench-i9.sh qwen3coderq4
```

To compare results, start with the generated `*-summary.tsv`, then inspect the referenced CSV files. Look for the highest prompt processing throughput (`pp`/prompt tok/s) that does not hurt generation throughput (`tg`/generation tok/s). For OpenCode, prefer the best overall balance over the absolute highest prompt-only score.

Summarize benchmark CSVs:

```bash
./summarize-bench.py bench-results/*-summary.tsv
```

`bench-results/` is ignored by git. Keep benchmark outputs local unless you explicitly want to share them for analysis.

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
| `qwen3coderq4` | Qwen3-Coder-30B-A3B-Instruct Q4\_K\_M | ~19 GB | 64 K | Main coding/docs model, 3B active |
| `qwen3coderq3` | Qwen3-Coder-30B-A3B-Instruct Q3\_K\_M | ~15 GB | 64 K | Faster coder-tier comparison |
| `qwen36u27bq5kp` | Qwen3.6-27B-Uncensored Q5\_K\_P | ~20 GB | 64 K | 27B dense — all params active |
| `qwen36u35bq4kp` | Qwen3.6-35B-A3B-Uncensored Q4\_K\_P | ~21 GB | 64 K | 35B MoE, 3B active |
| `gemma4q5km` | Gemma4-26B-A4B Q5\_K\_M | ~21 GB | 128 K | 26B MoE, 4B active |
| `supergemma4q4km` | SuperGemma4-26B-Uncensored Q4\_K\_M | ~17 GB | 128 K | Uncensored Gemma4 fine-tune |
| `glm47flashq5km` | GLM-4.7-Flash Q5\_K\_M | ~20 GB | 64 K | 30B MoE, 3B active, coding-focused |

GLM-4.7-Flash uses the DeepSeek-V2 MLA attention architecture and remains a useful comparison model, but measured slower than the Qwen MoE models on this i9. It scores ~59% on SWE-Bench Verified.

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

- `qwen3coderq4` best default row: ~142 prompt tok/s, ~32.5 gen tok/s at `8/24`
- `qwen3coderq3` fastest generation row: ~112 prompt tok/s, ~40.5 gen tok/s at `8/24` (quality check still needed)

### i9 speed notes

The i9 is CPU-only and AVX2-only, so dense 20 GB-class models are mostly memory-bandwidth bound. `qwen36u27bq5kp` is the highest-quality local option here, but it is not the fastest. For interactive coding latency, try these before changing infrastructure:

- Prefer `qwen3coderq4` for coding/docs work. Use `qwen3coderq3` only after checking quality on real OpenCode tasks.
- Keep context as low as the task allows; 64K/128K context improves long sessions but slows prompt processing and grows KV memory.
- Keep `qwen3coderq4` at 64K for OpenCode sessions that quickly fill context.
- Use `IK_LLAMA_THREADS=8` and `IK_LLAMA_THREADS_BATCH=24` as the default i9 startup point.
- Avoid `IK_LLAMA_THREADS=10` and `12`; benchmarks were consistently worse than `6` and `8`.
- Keep `qwen36u27bq5kp` for quality checks only. It is too slow for normal OpenCode loops.

### Completed i9 benchmark notes

The completed i9 `llama-bench` runs point to `8/24` as the best default thread setting. `8/32` is usually close, but not better enough to justify changing the default. The dense "fast" Qwen models were not actually fast on this AVX2 CPU.

Best observed rows:

| Use | Mode | Threads | Prompt tok/s | Gen tok/s | Notes |
|---|---|---:|---:|---:|---|
| Default coding/docs | `qwen3coderq4` | 8/24 | ~142 | ~32.5 | Conservative default; coding tuned |
| Faster coding candidate | `qwen3coderq3` | 8/24 | ~112 | ~40.5 | Fastest generation; validate quality manually |
| Prompt ingestion | `qwen36u35bq4kp` | 8/24–8/32 | ~152 | ~26–28 | Fastest prompt processing, less coding-specific |
| General fallback | `supergemma4q4km` | 8/24–8/32 | ~129 | ~23 | Decent non-Qwen fallback |
| GLM fallback | `glm47flashq5km` | 8/24 | ~92 | ~21 | Slower than expected here |
| Dense quality check | `qwen36u27bq5kp` | 8/24 | ~21 | ~3 | Quality-only, not interactive |

Rejected fast-tier candidates:

- `qwen3fast:q5` and `qwen3fast:q4` were much slower than the MoE models.
- `qwen38b:q5` and `qwen38b:q4` were faster than `qwen3fast`, but still not competitive with `qwen3coderq4`.
- `qwen36u35b:iq4nl` did not beat `qwen36u35b:q4kp`.

The benchmark script accepts legacy mode names like `qwen3coder` and explicit quantized presets like `qwen3coder:q4`, but the canonical script/OpenCode names include the quantization suffix.

The active benchmark set is `qwen3coderq4`, `qwen3coderq3`, `qwen36u27bq5kp`, `qwen36u35bq4kp`, `gemma4q5km`, `supergemma4q4km`, and `glm47flashq5km`.

The `all`, `today`, and `tomorrow` benchmark groups now use only the pruned active model list. `all` covers every active preset, `today` keeps the conservative comparison set, and `tomorrow` is the focused follow-up set. For normal future checks, benchmark explicit presets instead of rerunning the full matrix.

To free disk space after benchmarking rejected candidates:

```bash
./cleanup-models-i9.sh
./cleanup-models-i9.sh --apply
```

## Key lessons

1. **`-ngl 0` always** — integrated GPU causes Vulkan OOM crashes
2. **Quantized KV cache requires flash attention on** — `-ctv q8_0` is incompatible with `--flash-attn off`; ik_llama.cpp enables FA by default which is correct
3. **Avoid `_XL` variants** — incompatible quantization format with ik_llama.cpp
4. **ProBook: use generic AVX512 build** — `znver5` crashes with MoE models
5. **i9 has no AVX512** — despite being 13th gen Raptor Lake; use AVX2 build only
6. **Prompt cache is critical** — first message is slow; subsequent messages hit cache and are fast
7. **`-rea off`** — disables thinking mode; cuts response time 50–80% for coding tasks
8. **MoE active-parameter ceiling** — 3B active params is the real intelligence limit regardless of quantization level; for more intelligence use a dense model like `qwen36u27bq5kp`
9. **GLM-4.7-Flash is not faster than Qwen3-Coder on this i9** — despite MLA, measured throughput was lower than the Qwen MoE models
