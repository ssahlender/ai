#!/usr/bin/env bash
# Registers Graphify with Claude Code, Codex, and OpenCode.
set -euo pipefail

if ! command -v graphify >/dev/null 2>&1; then
  echo "graphify is not installed. Run ./graphify-install.sh first."
  exit 1
fi

echo "Registering Graphify for Claude Code..."
graphify install

echo "Registering Graphify for Codex..."
graphify install --platform codex

echo "Ensuring Codex multi_agent feature is enabled..."
python3 - <<'PY'
from pathlib import Path

path = Path.home() / ".codex" / "config.toml"
path.parent.mkdir(parents=True, exist_ok=True)
text = path.read_text() if path.exists() else ""
lines = text.splitlines()

out = []
in_features = False
features_seen = False
multi_agent_seen = False
inserted = False

for line in lines:
    stripped = line.strip()
    if stripped.startswith("[") and stripped.endswith("]"):
        if in_features and not multi_agent_seen:
            out.append("multi_agent = true")
            inserted = True
        in_features = stripped == "[features]"
        features_seen = features_seen or in_features
        multi_agent_seen = False if in_features else multi_agent_seen
        out.append(line)
        continue

    if in_features and stripped.startswith("multi_agent"):
        out.append("multi_agent = true")
        multi_agent_seen = True
    else:
        out.append(line)

if in_features and not multi_agent_seen:
    out.append("multi_agent = true")
    inserted = True
elif not features_seen:
    if out and out[-1] != "":
        out.append("")
    out.extend(["[features]", "multi_agent = true"])
    inserted = True

path.write_text("\n".join(out).rstrip() + "\n")
print(f"Codex config updated: {path}" if inserted or features_seen else f"Codex config unchanged: {path}")
PY

echo "Registering Graphify for OpenCode..."
graphify install --platform opencode

echo "Graphify registered. Restart Claude Code, Codex, and OpenCode sessions to load the new instructions."
