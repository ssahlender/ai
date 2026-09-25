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

## Using this ollama from another host (graphify on the Hermes LXC)

`start.sh` binds `OLLAMA_HOST=127.0.0.1` on purpose — an ollama endpoint has no
authentication, so it never listens on the LAN. Another host reaches it over an SSH
tunnel instead:

```bash
# client side, once per session. The concrete host, account and key path are
# deliberately NOT recorded in this repository — it is public. They live in the
# Hermes-local graphify-integration skill and the private Gitea repos.
ssh -f -N -o ExitOnForwardFailure=yes -i ~/.ssh/<key> <user>@<air-lan-address> \
    -L 11434:127.0.0.1:11434

export OLLAMA_BASE_URL=http://127.0.0.1:11434/v1   # graphify reads this one verbatim
export OLLAMA_API_KEY=dummy                        # graphify wants a non-empty value
```

Client-side findings (measured on the Hermes side with graphify 0.9.67, Sept 2026):

- **graphify batches documents into large chunks.** Ten small ESPHome YAML files went
  out as *one* ~18,755-token chunk, so cap it: `--token-budget 3000`.

- **The context window is a SERVER-side setting on ollama 0.34.4 — no client can raise it.**
  Verified on the wire 2026-09-25 with a logging proxy: graphify sent
  `options={'num_ctx': 16384} keep_alive='30m'`, and the runner still came up at
  **CONTEXT 4096** (`ollama ps`), i.e. `/v1` silently drops both fields. Only the native
  `/api/*` API honours them. Consequences: `GRAPHIFY_OLLAMA_NUM_CTX` does nothing;
  graphify's own derived `num_ctx` (`llm.py`) is dead code against `/v1`; and any request
  whose output needs more than `4096 - prompt` is cut off mid-answer
  (`truncated at max_completion_tokens`). The fix is `start.sh`
  (`OLLAMA_CONTEXT_LENGTH`, default 16384) — measured cost ~0.68 GB of q8_0 KV for this
  class of model (~42.5 KiB/token), so it is cheap on a 24 GB machine.
  Verify it on a LIVE request (`ollama ps` while a call is in flight), never on an idle one:
  an idle snapshot shows whatever the previous run left loaded.
- **Uncapped prompts kill big models.** An 18 GB model plus an 18.7K-token prompt dies
  with a Metal OOM (`mlx: [METAL] Command buffer execution failed: Insufficient
  Memory`). Capping the chunk fixes it; raising `iogpu.wired_limit_mb` is the other
  lever (see `../mlx/README.md`). Free RAM was not the cause — the Mac sat at 72% free
  with only ~2 GiB in apps when it happened.
- **`qwen2.5-coder:7b` is a weak-but-working extraction baseline, not a dead end.**
  Corrrected 2026-09-25 after re-measuring against a real corpus: with
  `--token-budget 3000` it produced **59 nodes / 83 edges over 8 files** in 1529 s, with
  3 `invalid JSON` and 6 hollow responses. An earlier "zero nodes" reading was a harness
  artifact, not the model's fault. Still: pick the extraction model by JSON-contract
  reliability and graph density, not by size or speed.
- The `ollama` Python module is *not* needed by graphify — it speaks the
  OpenAI-compatible `/v1/chat/completions` endpoint, so a failed call reports
  `Connection error`, never an import error. No server = connection refused.

