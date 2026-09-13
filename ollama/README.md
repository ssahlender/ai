# Ollama (MacBook Air M4, 24 GB) — daily-driver engine

Chosen over raw `mlx_lm.server` (`../mlx/`) and oMLX after a full comparison
on 2026-09-13 (see `../mlx/README.md` for the complete writeup). Ollama had
the fewest quirks and best throughput of the three:

| | Gen tok/s (warm) | Notes |
|---|---:|---|
| **Ollama + MLX backend** | **10-12** | Fastest; zero memory-guard failures across every test run |
| Raw `mlx_lm.server` | 6.5-6.6 | Open unpatched issue: unbounded KV-cache growth can crash on long sessions |
| oMLX | ~6.4 | Real memory-safety net, but needed per-use `--memory-guard-gb` tuning and repeatedly rejected requests even at generous ceilings |

## Install / update

Already fully wired into the shared `tools/` scripts:

```bash
cd ../tools
./ollama-install.sh          # brew install ollama
```

`ollama-update.sh` (binary) and `ollama-models-update.sh` (re-pulls every
currently-installed model) are both already in `tools/update-all.sh`'s
`UPDATE_TOOLS` list — `./update-all.sh` keeps everything current.

## Model

```bash
ollama pull qwen3.8:27b-mlx
```

Same model family as the MLX daily-driver candidate (`../mlx/README.md`),
but note: Ollama's `qwen3.8:27b-mlx` uses **nvfp4** quantization, not the
same 4-bit format as `mlx-community/Qwen3.8-27B-4bit` — a different build,
not just a different wrapper around the same weights. ~18 GB on disk.

## Scripts

| Script | Purpose |
|---|---|
| `start.sh` | Start `ollama serve` (flash-attention on, q8_0 KV cache) |
| `stop.sh` | Stop it |
| `setup-agent.sh` | Wire OpenCode + Pi provider config |

### Quick start

```bash
./start.sh
./setup-agent.sh
```

Model shortname in OpenCode/Pi: `ollama/qwen38-27b`. Default port `11434`
(override with `OLLAMA_HOST_PORT`).

## The one real quirk: `reasoning_effort`

Qwen3.8's chat template defaults to `reasoning_effort: xhigh` and burns most
of its token budget on `<think>` before answering. The fix is confirmed and
documented, but the *plumbing* differs by which API you call:

- **Ollama's native `/api/chat`**: `think` field, accepts
  `low`/`medium`/`high`/`none` — but this enum **doesn't match** Qwen3.8's own
  template enum (`low`/`medium`/`xhigh`). Passing `"think":"low"` silently did
  not reduce reasoning length in testing (2.69 tok/s effective — looked like a
  broken/slow engine until this was diagnosed).
- **Ollama's OpenAI-compatible `/v1/chat/completions`**: `reasoning_effort`
  field, accepts `"low"` directly and **does** map correctly to Qwen3.8's
  template. This is the endpoint that gave the real 10-12 tok/s numbers.

**Always use `/v1/chat/completions` with `"reasoning_effort": "low"`, never
`/api/chat` with `"think"`, for this model.**

Unlike `mlx_lm.server` (which bakes `reasoning_effort` into server startup via
`--chat-template-args`), Ollama has no server-wide equivalent — it must be set
per-request. If OpenCode/Pi's provider config doesn't expose a way to inject
extra body params, requests through the agent may still default to `xhigh`.
Direct API calls (e.g. the receipt-extraction/matching use case in
`receipt-extraction-guide.md`) always set it explicitly and are
unaffected.

## Also validated for non-coding use

The same engine (correctly configured) was used for a real accounting
extraction/matching task with 100% correct results — see
`receipt-extraction-guide.md`. Same model, same `reasoning_effort`
fix, different (single-turn, short) workload — the long-context/memory
tradeoffs from the coding-agent testing don't apply there.
