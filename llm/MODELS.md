# Local model provenance — exact sources

Every GGUF used for local inference on the x86 box (`C:\data\llm\models`), with its exact
HuggingFace repo, file, byte size and upstream SHA-256. **Verify after download**; the sizes are
exact, not rounded, and the hashes are the LFS object IDs published by HuggingFace.

Why this file exists: provenance was not recorded on the machine (the HF cache metadata was
empty), so a model on disk could not be traced back to a source without guessing. With this
table a model can be deleted and re-fetched exactly, which is what makes cleanup safe.

Verify a downloaded file (PowerShell):

```powershell
(Get-Item .\FILE.gguf).Length                                   # must equal the byte count
(Get-FileHash .\FILE.gguf -Algorithm SHA256).Hash.ToLower()     # must equal the hash
```

Download a file (resumable, verified): `llm/fetch-model.ps1`
(`llm/tests/download-model.ps1` is a thin wrapper over it, kept because other paths referred to it.)
Base URL pattern: `https://huggingface.co/<repo>/resolve/main/<file>`

## Installed right now (2026-09-27)

| host | runtime | model | size |
|---|---|---|---|
| ProBook `pmon-probook` (Windows) | mainline llama.cpp CPU, `C:\data\llm\llama.cpp-cpu` | `Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-IQ4_NL.gguf` | 18.42 GiB |
| MacBook Air M4 `pmon-macbookair` | Ollama (`ollama serve`) | `qwen36-35b-a3b` = `hf.co/unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q2_K_XL` (13 GB) | 11.45 GiB |

Nothing else is installed on either host. No GGUF lives on the Mac — Ollama owns its models — and
the ProBook's ik_llama engine directory was removed the same day, so the surviving engine there is
mainline (mode `qwen36u35b_ml`).

---

## In use — the reference model

### `Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-IQ4_NL.gguf`
| | |
|---|---|
| repo | `HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive` |
| URL | https://huggingface.co/HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive/resolve/main/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-IQ4_NL.gguf |
| bytes | `19779278976` (18.42 GiB) |
| sha256 | `b228c988c624dffe0b57235a395fa79562d4362fed545820f9b7d78908f337e6` |
| status | **KEEP** — the standing reference on this box |

35B-A3B MoE (≈3B active per token), so decode speed follows the 3B while memory follows the 35B.
Chosen because the box is memory-bandwidth-bound: a dense model of similar quality would move
several times the bytes per token.

### `Qwen3.6-35B-A3B-UD-Q2_K_XL.gguf` — the Mac's daily driver, via Ollama

| | |
|---|---|
| repo | `unsloth/Qwen3.6-35B-A3B-GGUF` |
| URL | https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF/resolve/main/Qwen3.6-35B-A3B-UD-Q2_K_XL.gguf |
| bytes | `12290628576` (11.45 GiB) |
| sha256 | `96b9c0af5c77a4ecaabe3983175112b5ece763261c1ece12b2494b692a70dad7` |
| fetched by | `ollama pull hf.co/unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q2_K_XL` — Ollama verified the sha256 itself, and the pull manifest ID `96b9c0af5c77` matches this hash |
| short name | `qwen36-35b-a3b` (derived model, `num_ctx 32768`, blobs shared with the tag above) |
| status | **IN USE** on the MacBook Air M4. Chosen over the 4-bit tier because ~17 GB does not fit: 17.6 GB OOM'd at 8K context and the guard aborts at 16.9 GB |
| differs from the reference | same model family, lower quant, and the base rather than the Uncensored fine-tune — the Mac runs a different quant on purpose, because it has a memory ceiling where this box has bandwidth |

## Other quants of the same repo

Same repo, same architecture. Kept only if a like-for-like quantisation comparison is wanted —
note that a like-for-like comparison must be **interleaved in one session**; runs taken hours
apart are not comparable on this hardware.

| file | bytes | sha256 |
|---|---|---|
| `…-IQ4_XS.gguf` | `18728777856` | `c26708a77a26d6c0416502832a200de4135e91af8279b5e93c67fe4e4e081aae` |
| `…-Q4_K_M.gguf` | `21166758016` | `bbef58c37ce88820be9d98b6437f1cf4bac890c947bd55fc7b68e22098574231` |
| `…-Q3_K_P.gguf` | `19023337600` | `18508f37fc7787f260df7ac1a3934b15dd9496d050b2d4b864241b493588fe95` |
| `…-IQ3_M.gguf` | `15440519296` | `4dd9a27c68bd778ede351a553680a1a6e4ec62e5d383b549892860ea337be0c0` |
| `…-Q2_K_P.gguf` | `14981265536` | `5a97f38db0ffb455bbcba7a7c7b8e82d1e42740ddd30893ac1ad57a2df5e94a4` |

## Evaluated, no advantage measured

| model | repo | file | bytes | sha256 |
|---|---|---|---|---|
| Ornith 1.5 35B-A3B | `ornith-ai/Ornith-1.5-35B-A3B-GGUF` | `Ornith-1.5-35B-Q4_K_M.gguf` | `21713463040` | `42739874cc2ccfdb8523b23fbe52e29b2a7555c8176737ca9ca0b5d59859d41f` |
| Qwen3.8 distill 35B-A3B | `empero-ai/Qwen3.8-35B-A3B-Distill-GGUF` | `Qwen3.8-35B-A3B-IQ4_XS.gguf` | `19627788160` | `b645af45431ef9b41f43cae51c9323b2d0ca84f23031d483d2105c643ae58d65` |
| Qwen-AgentWorld 35B-A3B | `unsloth/Qwen-AgentWorld-35B-A3B-GGUF` | `Qwen-AgentWorld-35B-A3B-UD-IQ4_XS.gguf` | `17785036032` | `ff4201b0c163950dc96aeaca033398543a1d62513ddc1c4030f9b94823764e06` |

- **Ornith** — vendor claims beat Qwen3.6-35B-A3B on repo-level benchmarks; no such advantage was
  reproduced locally. An independent bench found it decodes ~9% faster but loses prompt
  processing by a wide margin, and noted that every capability number in circulation traces back
  to the vendor's own unreproduced table. On the long-context task that previously crashed it, it
  passes with `--no-context-shift` (the crash is a partial-context-trim defect upstream, not a
  property of the weights).
- **Qwen3.8 distill** — no quality gain and no reproducible speed gain against the reference.
- **AgentWorld** — screened out earlier; that verdict is provisional, because it was measured
  while the evaluation harness still had known defects.

## Unverified — source not established

| file | bytes | note |
|---|---|---|
| `gemma-4-26B_q4_0-it.gguf` | `14439363584` | **source not confirmed.** It does not match the `HauhauCS/Gemma4-26B-A4B-QAT-Uncensored-HauhauCS-Balanced-MTP` quants (Q4_K_M there is `16796015520`). Never measured. Do not treat as reproducible until its origin is recorded or the file is replaced. |

---

## Rules this table exists to enforce

- A model on disk without a recorded source is not reproducible — record the repo, file, byte
  size and hash when downloading, not afterwards.
- Byte size alone is weak evidence; the SHA-256 is what proves a re-fetch is the same file.
- Public repo: nothing here may name an internal host, LAN address, account or key path.
