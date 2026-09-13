# MLX (MacBook Air M4, 24 GB)

[MLX](https://github.com/ml-explore/mlx-lm) — Apple's native ML framework — as a
second engine alongside the existing ik_llama.cpp/llama.cpp + Metal setup in
`../ik-llama/`. Not a replacement for that pipeline's structure, just a different
backend: same idea (`start.sh`/`setup-agent.sh` wiring OpenCode/Pi), different
runtime, model pulled straight from Hugging Face instead of a local GGUF.

## Setup

Install via the shared `tools/` install/update scripts (same pattern as every
other CLI tool in this repo):

```bash
cd ../tools
./mlx-lm-install.sh      # uv tool install mlx-lm
```

`mlx-lm` is also in `tools/update-all.sh`'s `UPDATE_TOOLS` list, so
`./update-all.sh` keeps it current alongside everything else. No Hugging Face
login needed — `mlx-community` and `LiquidAI` repos are public.

## Scripts

| Script | Purpose |
|---|---|
| `start.sh <mode>` | Start `mlx_lm.server` (OpenAI-compatible API) for a model in the `MODES` table |
| `stop.sh` | Stop the running server (`fuser -k` on `MLX_PORT`) |
| `setup-agent.sh` | Wire OpenCode + Pi provider config, parsed from `start.sh`'s `MODES` table |
| `bench.sh <hf-repo> [max-tokens]` | One-shot `mlx_lm.generate` throughput test, no server |

### Quick start

```bash
./start.sh qwen38-27b          # foreground; Ctrl-C to stop, or use ./stop.sh from another shell
./setup-agent.sh               # in another shell, once the server is up
```

`setup-agent.sh` writes provider `mlx` into `~/.config/opencode/opencode.json` /
`~/.local/share/opencode/auth.json` and `~/.pi/agent/models.json`, pointing at
`http://localhost:$MLX_PORT/v1` (default port `8090` — deliberately different
from ik-llama's `9080` so both can run side by side for comparison, memory
permitting). Model shortname in OpenCode/Pi: `mlx/qwen38-27b`.

### Environment overrides

| Var | Default | Purpose |
|---|---|---|
| `MLX_PORT` | `8090` | Server port |
| `MLX_REASONING_EFFORT` | `low` | Qwen3.8 chat-template reasoning level (`low`/`medium`/`xhigh`) — see below |
| `MLX_MAX_TOKENS` | `4096` | Default max generation tokens |

## Models

| Mode | Model | Size (4-bit) | Context | Notes |
|---|---|---:|---:|---|
| `qwen38-27b` | `mlx-community/Qwen3.8-27B-4bit` | ~15.5 GB | 128K (native) | Dense daily-driver candidate — see Results below |

## Key lesson: `reasoning_effort`

Qwen3.8-27B's chat template defaults to `reasoning_effort: xhigh` and will burn
an entire token budget on `<think>` before answering — with a short `--max-tokens`
it truncates before ever producing a real answer. `start.sh` sets
`--chat-template-args '{"reasoning_effort": "low"}'` by default (override with
`MLX_REASONING_EFFORT`) — confirmed via `mlx_lm.generate --chat-template-config`
to give clean, complete answers with only brief thinking.

## Results — 2026-09-13

Tested with `mlx_lm.generate` (no server yet at that point) against current
(Sept 2026) models, not the ones originally picked for this comparison —
`mlx-community` had already moved from Qwen3.6 to Qwen3.8 by the time this ran.

| Model | Size | Prompt tok/s | Gen tok/s | Peak mem | Notes |
|---|---:|---:|---:|---:|---|
| `mlx-community/Qwen3-14B-4bit` | ~8 GB | 20.5 | 12.4 | 8.4 GB | Previous-gen dense, baseline sanity check |
| `mlx-community/Qwen3.8-27B-4bit` | ~15.5 GB | 22.7–37.9 | **6.5–6.6** | 15.5 GB | Official successor to the `HauhauCS` Qwen3.6-27B fine-tune used as `qwen36u27b` in `../ik-llama/`. Needs `reasoning_effort: low` (see above). |
| `LiquidAI/LFM2-24B-A2B-MLX-4bit` | ~13.5 GB | 58.1 | 63.9 | 13.5 GB | 10x faster (2B active MoE) but noticeably lower quality — factually loose description of MoE routing in its own test answer. Vendor explicitly says it's not optimized for coding; it's a fast tool-dispatch/router model for agent inner loops, not a chat/coding daily driver. Tested, then **removed** — not a fit for this use case. |

**Verdict: `Qwen3.8-27B-4bit` is the daily-driver upgrade**, replacing the Qwen3.6-27B
fine-tune. Confirmed by public benchmarks too — big agentic/coding jump over 3.6
(SWE-bench Pro 53.5→61.7, DeepSWE 1.1 13.3→42.2). LFM2 was a different tool for a
different job (fast tool selection) — cache removed after the test (`rm -rf
~/.cache/huggingface/hub/models--LiquidAI--LFM2-24B-A2B-MLX-4bit`), 12 GB freed.

Tradeoff: 6.5 tok/s generation is slower than the i9's ~26 tok/s or ProBook's ~13 tok/s
for a comparable dense/MoE model — that's the M4 base chip's unified-memory bandwidth
ceiling for a 15.5 GB 4-bit model, not an MLX-vs-llama.cpp gap (no llama.cpp/Metal
number has been captured on the Mac for a direct comparison — still open, see below).

`mlx_lm.server` smoke-tested via `curl /v1/chat/completions` — OpenAI-compatible
API confirmed working with `reasoning_effort: low` applied server-wide.

## Engine comparison — 2026-09-13

Compared the same Qwen3.8-27B model across four engines on this Mac: raw
`mlx_lm.server`, Ollama + MLX backend, llama.cpp `llama-server` (GGUF), and
oMLX. First pass at the Ollama number was **wrong** — worth recording why,
since it changed the outcome.

**Round 1 (bugged):** Ollama tested via its native `/api/chat` with
`"think":"low"`, giving 2.69 tok/s — apparently much slower than raw MLX's 6.5.
Root cause found later: Ollama's `think` enum (`low`/`medium`/`high`/`none`)
doesn't match Qwen3.8's own template enum (`low`/`medium`/`xhigh`), so the
parameter silently didn't take effect and the model kept thinking at full
(`xhigh`) effort, burning most of the measured time. The fix is to use
`reasoning_effort` on Ollama's **OpenAI-compatible** `/v1/chat/completions`
endpoint instead, which does map correctly to Qwen3.8's template.

**Round 2 (also invalid):** retested the fixed parameter, but running Ollama
and oMLX loading a model *simultaneously* pushed this 24 GB machine into severe
memory pressure (~150 MB free, model process stuck in uninterruptible I/O
wait/swap thrashing) — invalidating that run too. Lesson: **test one engine at
a time** on a memory-constrained machine; concurrent large-model loads produce
garbage numbers, not a "multi-engine" data point.

**Round 3 (clean, isolated, one engine at a time):**

| Engine | Model file | Size | Gen tok/s (warm) | Notes |
|---|---|---:|---:|---|
| Raw `mlx_lm.server` | `mlx-community/Qwen3.8-27B-4bit` (MLX, standard 4-bit) | 15.5 GB | 6.5–6.6 | No safety rails; has basic built-in prompt caching (confirmed: 56→189 cached tokens across a 3-turn test) |
| **Ollama 0.33.3 + MLX backend** | `qwen3.8:27b-mlx` (**nvfp4** quant — different format from mlx-community's 4-bit, a real confound, not just "a wrapper") | 18 GB | **10–12.2** | Fastest of the three once correctly configured; clean prompt caching (52→210 cached tokens) |
| llama.cpp `llama-server` | `unsloth/Qwen3.8-27B-UD-Q4_K_XL.gguf` | 17.6 GB | 4.56 (4K ctx only) | Unsloth's "dynamic" quant is bigger than the MLX 4-bit build — OOM'd at 8K+ context on this 24 GB machine, needed `--parallel 1` (ik-llama's own documented lesson) just to get that far |
| oMLX 0.6.4 | `mlx-community/Qwen3.8-27B-4bit` (same MLX file as raw server) | 15.5 GB | ~6.4 | Same speed as raw MLX (expected — same underlying engine), but with a real memory-safety enforcer (see below) |

**Corrected takeaway: Ollama's MLX backend is fastest for raw single-turn
generation on this machine**, not raw `mlx_lm.server` as first concluded —
that first conclusion was an artifact of a misconfigured test parameter, not a
real engine difference. Cross-checked against general public benchmarks too:
MLX is broadly reported 15–25% faster than llama.cpp for 14B+ models, and
Ollama itself switched its Apple Silicon backend to MLX in March 2026
(stable/default since v0.30, May 2026) — consistent with Ollama being
competitive here once configured correctly.

The llama.cpp GGUF path was deleted after testing (17.6 GB freed) — clearly
memory-constrained on this specific 24 GB machine with this specific quant.

### oMLX — proven memory safety, caching not yet demonstrated

[oMLX](https://github.com/jundot/omlx) (genuine upstream verified: 21.6k
stars, active — beware many identically-named/described GitHub forks, that's
normal fork behavior, not spam) is a server built specifically for "coding
agents on Apple Silicon" with a documented process-memory enforcer and tiered
(RAM + paged-SSD) KV caching.

**Memory safety: proven, not just documented.** With the default `balanced`
tier, the exact model that raw `mlx_lm.server` runs fine on this machine
(15.5 GB) got a **clean, actionable rejection** instead of a crash:

> `process memory limit exceeded (usage 17.7 GB, abort threshold 16.9 GB,
> metal_cap ceiling 17.8 GB)`

Fix: `--memory-guard aggressive` plus raising macOS's Metal wired-memory cap
(`sudo sysctl iogpu.wired_limit_mb=20480` — temporary, resets on reboot). After
that, generation worked normally. This is the mechanism that should prevent
the kernel-panic class of bug documented for raw `mlx_lm.server` below.

**Caching: not demonstrated by this test, likely due to test design, not a
flaw.** A 3-turn conversation (57–302 tokens per turn) showed `cached_tokens: 0`
throughout, even with `--hot-cache-max-size` and `--paged-ssd-cache-dir`
explicitly enabled (both default OFF — easy to miss). Server log explained why:
cache operates in **2048-token blocks**
(`boundary_snapshot_unavailable ... available_boundaries=0`), and the test
conversation never got close to one full block. Real OpenCode sessions
(system prompt + file contents) would clear 2048 tokens quickly — this needs a
realistic longer-context test to actually observe, not a toy Q&A exchange.

Install note: the Homebrew tap path (`brew tap jundot/omlx <url>`) hit
formula-loading and `git` auth errors on this machine's modified Homebrew
build — used `pip install -e .` from a cloned source checkout instead, which
worked cleanly. No custom Metal kernels needed for Qwen3.8 specifically (only
GLM-5.2/MiniMax M3/Qwen3.5 need those, per the project's own docs) — Xcode is
not required for this use case.

### Known risk (raw `mlx_lm.server`): accepted, with mitigation

`mlx_lm.server` has open upstream issues about unbounded KV-cache growth during
long agentic sessions, up to a macOS kernel panic on a 96 GB Mac Studio after
~58K tokens ([ml-explore/mlx-lm#883](https://github.com/ml-explore/mlx-lm/issues/883),
[#1390](https://github.com/ml-explore/mlx-lm/issues/1390),
[#1672](https://github.com/ml-explore/mlx-lm/issues/1672)) — root cause: no
`--max-kv-size` support on the server ([#615](https://github.com/ml-explore/mlx-lm/issues/615),
still open). This Air has 24 GB, less headroom than that Mac Studio. Accepted
for now since it only bites at very long (50K+ token) unbounded sessions — mitigate by
restarting the server between long OpenCode sessions rather than leaving it up
indefinitely, and revisit if `--max-kv-size` lands on the server.

### Current state (2026-09-13, backlogged — no rush, this is a months-scale decision)

- Ollama and oMLX are both **kept installed** via Homebrew (binaries only,
  nothing running, no idle resource cost) so testing can resume without
  re-setup. Ollama's `qwen3.8:27b-mlx` (17 GB) is also kept on disk.
- Neither engine is wired into OpenCode yet — no daily-driver decision has been
  made. Current OpenCode config still points at `../ik-llama/`
  (llama.cpp/`qwen36u27b`).
- `mlx-community/Qwen3.8-27B-4bit` (15.5 GB, standard 4-bit MLX) stays cached —
  used by both raw `mlx_lm.server` and oMLX tests.

### Backlog: realistic long-context test (oMLX caching)

oMLX's headline feature — tiered KV caching across turns — needs a test with
a genuinely long shared prefix (2048+ tokens: a real system prompt or a pasted
code file) to actually observe a cache hit, not a short Q&A exchange like the
one run above. Do this before ruling oMLX in or out on caching grounds; its
proven memory-safety behavior already stands on its own regardless.

### Not yet done

- `reasoning_effort: low` only smoke-tested on short prompts — not yet run
  through an actual OpenCode coding/tool-call session, on any engine.
- Not yet decided: keep `qwen36u27b` (llama.cpp/GGUF, `../ik-llama/`) as the
  OpenCode daily driver and treat MLX/Ollama/oMLX as second options, or switch
  the daily driver over and update `../ik-llama/README.md`'s Mac table
  accordingly. Candidates ranked by what's known so far: Ollama (fastest,
  proven caching) vs. oMLX (same speed as raw MLX, proven crash-safety, caching
  unproven) vs. raw `mlx_lm.server` (no longer favored — same speed as oMLX
  without its safety net, slower than Ollama).
