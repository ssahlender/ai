# ProBook (Windows 11): mainline llama.cpp

Measurements, background and lessons. How to start, stop and wire things is in [`../README.md`](../README.md); the live model list is [`../models.json`](../models.json).
Commands below run from `llm\probook\`.

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
  (`/v1`) both work. See [`mac.md`](mac.md).

## Benchmarks, engines, models

| script | use |
|---|---|
| `bench\bench-matrix.ps1` | measures **every `.gguf` found in the models dir**, discovered at run time, so it cannot outlive its models |
| `bench\bench-ab.ps1`, `bench\bench-mtp.ps1` | **obsolete** (they required gemma-4-26B and the ik_llama engine). Kept as the method's record; they refuse and point at `bench-matrix.ps1` |
| `update-llm.ps1` | updates engines; default is `mainline` only. `-Engine ik_llama`/`llama-swap`/`all` bring the others in deliberately |
| `llama-swap-setup.ps1` | optional model routing/lifecycle via llama-swap, same stack as `llm/i9/llama-swap-setup.sh`; install the binary first with `update-llm.ps1 -Engine llama-swap`. verified end to end on the ProBook 2026-10-28 (llama-swap v268); run `-WhatIf` first |
| `fetch-model.ps1` | resumable, size-verified GGUF download |
| `MODELS.md` | provenance: repo, exact bytes, SHA-256, and what is installed on which host |

## Tests

`llm\tests\` holds the quality harness (task set, deny policy, verdict rule, evidence publishing).
Its own self-tests are run by a scratch clone so they cannot disturb this working tree. Two of the
five still fail (deny-gate smuggling routes, derivability guard); the fixes are pending on the
`fix/harness-integrity` branch, and it is deliberately unmerged until its own gate passes.

## History: before 2026-10-28

From the WSL and HauhauCS era (until 2026-10), kept for the method and the numbers; none of these modes is live.

### ProBook (32 GB RAM)

| Mode | Model | Size | Context | Vision | Notes |
|---|---|---|---|---|---|
| `qwen36u35b` | Qwen3.6-35B-A3B-Uncensored IQ4\_NL | ~16 GB | 32 K | no | 35B MoE, 3B active |
| `qwen3coder30b` | Qwen3-Coder-30B-A3B Q4\_K\_M | ~19 GB | 64 K | no | Dedicated agentic coder, 262K native ctx |

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

**qwen3coder30b (Q4\_K\_M, ~19 GB):** benchmarks pending; run via `bench\bench-threads.ps1` (no longer in the repo) after download.

Default `8/16` is the best balanced setting for qwen36u35b. Use `8/8` (`IK_LLAMA_THREADS=8 IK_LLAMA_THREADS_BATCH=8`) only if qwen prompt throughput is the priority.
