#!/usr/bin/env python3
"""Remove one key from an agent's JSON or YAML config (the reverse of what the *-init.sh scripts add).

    _config-remove.py [--dry-run] <file> <key.path>

The key path is dot-separated, e.g. `mcp.repomix`. Format follows the extension (.json, .yaml/.yml).
A missing file or key is not an error; nothing else in the file is touched.
"""
import json
import sys
from pathlib import Path


def main():
    args = sys.argv[1:]
    dry = args[:1] == ['--dry-run']
    if dry:
        args = args[1:]
    if len(args) != 2:
        sys.exit(__doc__.split('\n\n')[1].strip())
    path, keys = Path(args[0]), args[1].split('.')
    label = f'{path}: {args[1]}'
    if not path.is_file():
        print(f'  {label}: not present (no file)')
        return
    yaml_file = path.suffix in ('.yaml', '.yml')
    if yaml_file:
        try:
            import yaml
        except ImportError:
            print(f'  {label}: skipped (pyyaml missing); remove it by hand')
            return
        data = yaml.safe_load(path.read_text()) or {}
    else:
        data = json.loads(path.read_text())
    parent = data
    for k in keys[:-1]:
        parent = parent.get(k) if isinstance(parent, dict) else None
    if not isinstance(parent, dict) or keys[-1] not in parent:
        print(f'  {label}: not present')
        return
    if dry:
        print(f'  {label}: would remove')
        return
    del parent[keys[-1]]
    if yaml_file:
        path.write_text(yaml.dump(data, default_flow_style=False, sort_keys=False))
    else:
        path.write_text(json.dumps(data, indent=2) + '\n')
    print(f'  {label}: removed')


if __name__ == '__main__':
    main()
