# Local LLM for receipt/OCR structured extraction and ledger matching

Use case: a Codex/agent pipeline (e.g. the Accounting Helper project on
`pmon-macbookair`) OCRs receipts locally (Apple Vision, see
`MAC_WORKER.md` in that project). Two things currently cost the cloud agent
tokens/context that a local model can do instead, for free:

1. **Extraction** — turning raw OCR text into compact structured JSON
   (vendor, date, amount, currency) instead of the cloud agent reading raw
   OCR text on every receipt.
2. **Matching** — given a receipt's extracted data and a short list of
   candidate open ledger entries, deciding which one it corresponds to (the
   actual "brain work" of reconciliation — not just field extraction).

Both were tested against real, already-verified cases from this project's own
Phase 2 output (2026-09-13) — not synthetic examples. Exact figures/vendor
names are intentionally omitted here (this is a shared dev-tools repo, not
the accounting workspace) — see the project's own `outputs/*/ocr/README.md`
files for the underlying verified data.

**Extraction, validated:** ran one already-verified single-page invoice's OCR
JSON through the extraction prompt below. Model output matched the project's
own manually-verified reading of that document exactly (vendor, ISO date,
currency, amount all correct).

**Matching, validated — the harder, more valuable case:** three invoices from
the same vendor, same booking date, even the same source PDF filename in the
ledger export, differing only in description and amount. Given one invoice's
raw OCR text plus all three as candidates, the model correctly picked the
matching entry with high confidence and a correct one-sentence justification,
rejecting the two lookalikes — replicating the same conclusion the project's
own OCR README already reached by hand. This is the part worth automating:
it's exactly the kind of multi-file cross-referencing (OCR text ↔ ledger CSV
rows) that otherwise costs the cloud agent real context/tokens per receipt.

This is a different workload than the daily-driver coding-agent evaluation
that chose this engine — single-turn, short input/output, no multi-turn
context growth — so the memory-guard/long-context tradeoffs from that
comparison don't apply here. **Engine: Ollama** (the settled daily driver,
chosen after a full comparison against raw MLX and oMLX on speed,
crash-safety, and quirks — full writeup at
`~/data/git/ai-tools/ollama/README.md` on this Mac).
Both the extraction and matching prompts below were re-verified directly
against Ollama specifically, not just the MLX engine used during initial
exploration — same correct results.

## Starting the engine

```bash
cd ~/git/ai-tools/ollama
./start.sh
```

Check it's up:

```bash
curl -s http://127.0.0.1:11434/v1/models
```

## Extraction call

Use `reasoning_effort: low` on the **OpenAI-compatible endpoint**
(`/v1/chat/completions`) — this is a short structured-output task, not a
reasoning task, and `xhigh` (the model's default) wastes time thinking.
**Do not use `/api/chat`'s `think` field** — its enum
(`low`/`medium`/`high`/`none`) doesn't match this model's own template enum
(`low`/`medium`/`xhigh`) and silently fails to reduce reasoning: passing
`"think":"low"` on the native endpoint measured 2.69 tok/s (looked like a
broken/slow engine); `"reasoning_effort":"low"` on the OpenAI-compatible
endpoint measured 10-12 tok/s with the same model, same hardware.

```bash
curl -s http://127.0.0.1:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3.8:27b-mlx",
    "reasoning_effort": "low",
    "messages": [
      {"role": "system", "content": "Extract vendor, date (ISO YYYY-MM-DD), currency, and total amount from this OCR receipt text. Output ONLY a JSON object with keys: vendor, date, currency, amount. If a field is not clearly present in the text, use null for that field — never guess or invent a value."},
      {"role": "user", "content": "<PASTE RAW OCR TEXT HERE>"}
    ],
    "max_tokens": 200
  }'
```

The `null`-instead-of-guessing instruction matches the Accounting Helper
project's own rule (`AGENTS.md`: "Do not invent missing dates, counterparties,
receipt links, categories, amounts, or tax treatment. Mark them for review.")
— any field the model can't find stays `null` and gets flagged for human
review downstream, same as the existing pipeline already does for unmatched
receipts.

## Matching call

Same `reasoning_effort: low`. Pass the receipt's raw OCR text plus a *short*
list of candidate ledger entries (already narrowed down by date/amount range
or counterparty — don't hand it the whole ledger) and ask for a matched key,
confidence, and reason:

```bash
curl -s http://127.0.0.1:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3.8:27b-mlx",
    "reasoning_effort": "low",
    "messages": [
      {"role": "system", "content": "You are matching a scanned invoice (raw OCR text) to the correct existing ledger entry from a short candidate list. Read the OCR text, identify the vendor, invoice type, and total amount, then pick the candidate entry_key whose description and amount best match. Output ONLY a JSON object with keys: matched_entry_key (string or null), confidence (\"high\"/\"medium\"/\"low\"), reason (one short sentence). If no candidate clearly matches, or more than one could plausibly match, use null and explain why in reason — never guess."},
      {"role": "user", "content": "OCR text:\n<PASTE RAW OCR TEXT>\n\nCandidate ledger entries:\n<PASTE 2-5 CANDIDATE ROWS AS JSON>"}
    ],
    "max_tokens": 400
  }'
```

`max_tokens` needs headroom for the model's `<think>` preamble even at low
effort — 200 was too tight for this prompt shape and returned no `content` at
all; 400-600 worked reliably in testing. Only the matching prompt needed the
larger budget; the pure-extraction prompt worked fine at 200.

This step should stay a **proposal**, same as the existing pipeline's
`receipt_match_status: matched/ambiguous/missing_or_unmatched` convention —
even a "high confidence" model match goes through the same human review the
project already requires before anything is booked or renamed.

## Model choice

`qwen3.8:27b-mlx` (or the MLX-native `mlx-community/Qwen3.8-27B-4bit`) is
already downloaded and known-good from today's testing, so it's the
zero-extra-setup choice. For pure structured extraction on short text, a much
smaller model (7-14B) would likely be faster and sufficient — worth trying if
extraction volume grows large enough that per-receipt latency matters. Not
tested here; the flagship model was simply what was already on hand.

## Practical context size on this Mac

The model's architectural max context is 262,144 tokens, but that's not the
real ceiling on a 24 GB machine. In testing during engine evaluation, a single
~3.9K-token prompt already pushed KV cache usage to 17-18 GB on top of the
15.5 GB model weights — right against a memory guard's ceiling (that specific
test was on oMLX, which enforces a hard ceiling; Ollama doesn't hard-fail the
same way but the underlying memory pressure is the same). Rough estimate from
that data: realistic safe context
for a single request here is more like **8K-16K tokens**, not benchmarked
precisely. For this receipt-matching use case that's not a constraint — OCR
text for one invoice plus a handful of candidate ledger rows is a few hundred
to low thousands of tokens, well within range. It would matter if this were
ever extended to feed the model much larger batches (e.g. many receipts or a
large ledger excerpt) in one call.

## Verified

Both prompts above were run against real project data on 2026-09-13, not
hypothetical examples, and both were confirmed specifically on Ollama (not
just during the initial multi-engine exploration): the extraction case
(one already-verified single-page invoice) and the matching case (3-way
disambiguation between lookalike invoices from the same vendor) both returned
the same correct results on Ollama as they did on the other engines tested
during evaluation. Before extending beyond these two verified cases,
spot-check a few more receipts against their already-known-correct answers
(the project's `outputs/*/ocr/README.md` files record several) before
trusting it across a full batch unattended.
