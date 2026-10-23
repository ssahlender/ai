#!/usr/bin/env python3
"""Merge the remote-control block into a system policy without replacing other keys."""
import json
import os
from pathlib import Path
import re
import sys
import tempfile


def update_policy(agent, path):
    original = path.read_text() if path.exists() else ""
    if agent == "claude":
        data = json.loads(original or "{}")
        data["disableRemoteControl"] = True
        updated = json.dumps(data, indent=2) + "\n"
    else:
        import tomllib  # Python 3.11+: validate before modifying a managed policy.

        data = tomllib.loads(original)
        if data.get("allow_remote_control") is False:
            return
        # Try replacing each matching assignment, accepting only a semantic
        # match. This avoids mistaking table headers/keys inside strings for TOML.
        expected = dict(data, allow_remote_control=False)
        lines = original.splitlines(keepends=True)
        candidates = ["allow_remote_control = false\n" + original]
        for i, line in enumerate(lines):
            if re.match(r"\s*(?:allow_remote_control|\"allow_remote_control\"|'allow_remote_control')\s*=", line):
                candidates.append("allow_remote_control = false\n" + "".join(lines[:i] + lines[i + 1:]))
        for candidate in candidates:
            try:
                parsed = tomllib.loads(candidate)
            except tomllib.TOMLDecodeError:
                continue
            if parsed == expected:
                updated = candidate
                break
        else:
            raise ValueError("Cannot merge remote-control key without changing unrelated settings")
    if updated == original:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    # Atomic replacement: malformed input or interrupted writes leave the policy intact.
    fd, name = tempfile.mkstemp(dir=path.parent, prefix=".remote-control-")
    try:
        with os.fdopen(fd, "w") as output:
            output.write(updated)
            os.fchmod(output.fileno(), path.stat().st_mode & 0o777 if path.exists() else 0o644)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


if __name__ == "__main__":
    if len(sys.argv) > 3 and sys.argv[3] == "--check":
        path = Path(sys.argv[2])
        if not path.exists():
            sys.exit(1)
        if sys.argv[1] == "claude":
            enabled = json.loads(path.read_text()).get("disableRemoteControl") is True
        else:
            import tomllib

            enabled = tomllib.loads(path.read_text()).get("allow_remote_control") is False
        sys.exit(0 if enabled else 1)
    update_policy(sys.argv[1], Path(sys.argv[2]))
