# Agent Configuration

How to wire AI coding agents to the tools in this repo.

## This repository is PUBLIC

This repository is public (its own URL is the only GitHub reference that belongs here). Never
commit internal addressing: no LAN
IPs, internal hostnames, account names, SSH key filenames/paths, or
private URLs. Keep the real values in host-local skills or a private repository
and reference them from here (`llm/docs/mac.md` shows the pattern). The same
rule applies to `sysadmin-github`.

## Re-syncing an existing clone after the history rewrite (2026-10-06)

History on `main` and `fix/harness-integrity` was rewritten and force-pushed. Every other clone
(MacBook, ProBook, agent checkouts) must be re-synced; do not `git pull` or merge, that mixes old
and new history:

```bash
git branch backup-before-resync          # keep any unpushed local work reachable
git fetch --prune origin && git reset --hard origin/main
```

`reset --hard` discards local changes and commits on the current branch, so save anything
unpushed first (the backup branch above, or `git stash`). Recreate other local branches on top of
the new history with `git rebase --onto`, or `git cherry-pick` their commits.

Commits here must use a personal identity, not a corporate address. Set it per clone with
`git config --local user.name` / `user.email`; the global git config may point elsewhere.

## Local LLM (OpenCode + Claude Code)

Everything lives in [`llm/`](llm/README.md): one folder per machine (`probook/`, `i9/`, `mac/`), the shared
catalog `llm/models.json` and proxies in `llm/shared/`. Agent wiring, Claude Code env vars, the
attribution-header slowdown (~90 %), the proxies and llama-swap: [`llm/docs/agents.md`](llm/docs/agents.md).
Model ids (one readable name per model, the `id` in `llm/models.json`) and provider ids (`ik-llama`,
`ollama`, `llamacpp`) are part of the agents' configs: do not rename them as a side effect. If a rename is
asked for, `llm/setup-agents.sh` / `setup-agents.ps1` replaces the old ids and removes references to them.

## tools/ scripts

No special agent config needed, scripts are self-contained bash. Run directly or via `update-all.sh`.

On the i9, scripts use the `_brew-i9.sh` helper which runs brew via `sudo -n -u brewuser` with the full absolute path. Other machines run brew directly.

## Graphify: Knowledge Graphs (per-agent skills)

`graphify` turns a folder of code/docs/papers/images into a queryable knowledge
graph (`graphify-out/graph.json` + `GRAPH_REPORT.md` + `graph.html`).

Install/uninstall/update: `tools/graphify-install.sh` → `graphify-init.sh`
(`graphify-update.sh` refreshes both; it is in `update-all.sh`).

### Install shape

`uv tool install 'graphifyy[openai,ollama,sql,terraform,leiden,mcp,watch,office,pdf]'`:
isolated venv at `$(uv tool dir)/graphifyy`, shim `~/.local/bin/graphify`.
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

### Two registration levels: do not confuse them

1. **`graphify install --platform <p>`, user-level, what the init script does.**
   Copies the skill only:
   - Claude Code `~/.claude/skills/graphify/`
   - Codex `~/.codex/skills/graphify/`
   - OpenCode `~/.config/opencode/skills/graphify/` (also auto-loads `~/.claude/skills/`)
   - the agent host's own graphify skill directory (outside this repo)
   - Antigravity `~/.gemini/config/skills/graphify/` (agy reads that path globally;
     project-level is `<workspace>/.agents/skills/`)

2. **`graphify <platform> install`, PROJECT-scoped, run it inside the repo.**
   Writes always-on wiring into `$PWD`: `AGENTS.md` (codex/opencode), `CLAUDE.md` +
   `.claude/settings.json` PreToolUse hooks (claude), `.codex/hooks.json` (codex),
   `.agents/rules|workflows/*.md` (antigravity), `.opencode/opencode.json` + plugin
   (opencode). It **touches committed files**, so it is opt-in per repo.

Because of (2), `graphify-init.sh` runs the OpenCode registration inside a
throwaway `mktemp -d`, otherwise the script drops `.opencode/` into whatever
repo it was invoked from.

### LLM backend

Code-only corpora need **no API key**: AST extraction, clustering, labels, query,
and `GRAPH_REPORT.md` all work keyless. Docs/papers/images need a backend:
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
