# Agent Configuration

How to wire AI coding agents to the tools in this repo.

## This repository is PUBLIC

`github.com/ssahlender/ai` is public. Never commit internal addressing to it: no LAN
IPs, internal hostnames, account names, SSH key filenames/paths, or
private URLs. Keep the real values in the Hermes-local skills or the private Gitea
repos and reference them from here — `ollama/README.md` shows the pattern. The same
rule applies to `sysadmin-github`.

## Local LLM (OpenCode + Claude Code)

### x86 CPU (ProBook + i9)

See [`ik-llama/AGENTS.md`](ik-llama/AGENTS.md) for full setup:

- OpenCode provider config (setup scripts for ProBook and i9)
- Claude Code environment variables and model names
- Disabling the KV cache attribution header (causes ~90% slowdown with local servers)
- OpenCode local-speed mode for disabling MCP/plugins when local writes stall with low CPU
- WSL2 memory config
- Prompt cache warmup tip

### Apple Silicon (MacBook Air M4)

See [`ik-llama/`](ik-llama/) for unified setup:
- `download-models.sh macbook-air` — pulls GGUFs + mmproj from HF (same repos as i9)
- `setup-agents.sh macbook-air` — auto-generates OpenCode/Pi config
- `start.sh macbook-air` — Metal GPU via brew's llama.cpp, same flags + vision as i9

## tools/ scripts

No special agent config needed — scripts are self-contained bash. Run directly or via `update-all.sh`.

On the i9, scripts use the `_brew-i9.sh` helper which runs brew via `sudo -n -u brewuser` with the full absolute path. Other machines run brew directly.

## Headroom — Context Compression (MCP + Proxy)

Headroom compresses tool outputs, files, and text before they reach the LLM (40-90% savings).

### MCP (universal — all agents)
Add to agent MCP config:
```json
{"mcpServers": {"headroom": {"command": "headroom", "args": ["mcp", "serve", "--proxy-url", "http://127.0.0.1:8788"]}}}
```
Tools: `mcp_headroom_headroom_compress`, `_retrieve`, `_stats`.

Hermes: `mcp_servers.headroom` in `~/.hermes/config.yaml` (already configured).
Claude Code: `headroom mcp install --agent claude` (already configured).

### Proxy (transparent — Claude Code / Codex)
```bash
headroom proxy --port 8788          # already running as systemd service
headroom wrap claude                # one-time setup
headroom wrap codex                 # one-time setup
```

### ai-tools scripts
- `tools/headroom-install.sh` — uv tool install headroom-ai[proxy]
- `tools/headroom-update.sh` — uv tool upgrade (also in update-all.sh)
- `tools/headroom-init.sh` — systemd service + wrapper scripts
- `tools/headroom-mcp-init.sh` — MCP config for all agents

## Graphify — Knowledge Graphs (per-agent skills)

`graphify` turns a folder of code/docs/papers/images into a queryable knowledge
graph (`graphify-out/graph.json` + `GRAPH_REPORT.md` + `graph.html`).

Install/uninstall/update: `tools/graphify-install.sh` → `graphify-init.sh`
(`graphify-update.sh` refreshes both; it is in `update-all.sh`).

### Install shape

`uv tool install 'graphifyy[openai,ollama,sql,terraform,leiden,mcp,watch,office,pdf]'`
— isolated venv at `$(uv tool dir)/graphifyy`, shim `~/.local/bin/graphify`.
**Not a brew package.** The PyPI name is `graphifyy` (double-y); the CLI is `graphify`.

Extras worth knowing (each one silently disabled when absent):

| Extra | Provides | Symptom when missing |
|---|---|---|
| `terraform` | `tree_sitter_hcl` | **every `.tf`/`.hcl` file contributes nothing** (warning: `tree_sitter_hcl not installed`) |
| `leiden` | `graspologic` | no Leiden community detection |
| `mcp` | `mcp` SDK | `graphify --mcp` stdio server unusable |
| `watch` | `watchdog` | `--watch` auto-rebuild unusable |
| `pdf` / `office` / `sql` | doc parsers | those file types are skipped |

On i9 the `pdf` extra is omitted (corporate proxy CVE filter blocks `pypdf`).

### Two registration levels — do not confuse them

1. **`graphify install --platform <p>` — user-level, what the init script does.**
   Copies the skill only:
   - Claude Code `~/.claude/skills/graphify/`
   - Codex `~/.codex/skills/graphify/`
   - OpenCode `~/.config/opencode/skills/graphify/` (also auto-loads `~/.claude/skills/`)
   - Hermes `~/.hermes/skills/graphify/`
   - Antigravity `~/.gemini/config/skills/graphify/` (agy reads that path globally;
     project-level is `<workspace>/.agents/skills/`)

2. **`graphify <platform> install` — PROJECT-scoped, run it inside the repo.**
   Writes always-on wiring into `$PWD`: `AGENTS.md` (codex/opencode), `CLAUDE.md` +
   `.claude/settings.json` PreToolUse hooks (claude), `.codex/hooks.json` (codex),
   `.agents/rules|workflows/*.md` (antigravity), `.opencode/opencode.json` + plugin
   (opencode). It **touches committed files**, so it is opt-in per repo.

Because of (2), `graphify-init.sh` runs the OpenCode registration inside a
throwaway `mktemp -d` — otherwise the script drops `.opencode/` into whatever
repo it was invoked from.

### LLM backend

Code-only corpora need **no API key**: AST extraction, clustering, labels, query,
`GRAPH_REPORT.md` all work keyless. Docs/papers/images need a backend —
`--backend gemini|kimi|claude|openai|deepseek|ollama`, or a local
OpenAI-compatible server via `OPENAI_BASE_URL`/`OPENAI_MODEL`.
`--backend claude` requires `ANTHROPIC_API_KEY`; it does **not** reuse a Claude
Code subscription login. Keyless doc corpora: use `--code-only`.

## Large Generated Files

Do not write large generated artifacts such as draw.io XML, SVG, lock files, or
large JSON blobs as one inline tool-call string. Local OpenCode/Qwen tool calls
can fail with JSON parse errors when a large payload contains quoting,
newlines, or truncated strings.

For generated artifacts, create a small generator script or structured source
file, run it to write the artifact, and validate the result. If literal content
is unavoidable, write it in smaller chunks and verify the final file.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- Dirty graphify-out/ files are expected after hooks or incremental updates; dirty graph files are not a reason to skip graphify. Only skip graphify if the task is about stale or incorrect graph output, or the user explicitly says not to use it.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
