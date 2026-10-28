#!/usr/bin/env python3
"""Shared loader for llm/models.json -- the single source of truth for every
machine's model lineup (i9, macbook-air, probook). Every bash script that needs model
data calls this instead of embedding its own copy of the parsing logic: that duplication
(and start.sh re-deriving it from positional pipe fields) was flagged in a 2026-10-28
review (codex + agy) as the main scalability risk once more machines/models/colleagues
show up. PowerShell is NOT routed through this -- ConvertFrom-Json there is already a
real structured-data path, not a copy-pasted parser, so it keeps reading models.json
directly.

File resolution (first match wins), unless an explicit path is passed:
  1. $IK_LLAMA_MODELS_JSON   (env var; an explicit one-off override)
  2. models.local.json in llm/ next to models.json (gitignored colleague override --
     see models.local.json.example)
  3. models.json in llm/, one level above this script (the committed, shared lineup)

As a library (used by setup_agents.py and llama-swap-setup.sh, which need the raw
per-mode dicts to build their own structures):
    from models import load_modes, resolve_models_json
    modes = load_modes('i9')                     # list of dicts, as stored in the JSON
    path  = resolve_models_json()                 # the file that was actually used

As a CLI (used by start.sh, download-models.sh, model-info.sh, cleanup-models.sh,
bench.sh, each of which only needs one fixed, already-established output shape):
    models.py modes      <machine>   pipe-delimited: desc|file|ctx|cram|YARN|SAMPLE|mmproj|spec|CT
                                      (exactly the shape start.sh's MODES array always used)
    models.py downloads  <machine>   tab-delimited: local_name<TAB>repo<TAB>repo_file<TAB>bytes
                                      (one row per downloadable file: model + its mmproj, if any)
    models.py info       <machine>   tab-delimited: desc<TAB>file<TAB>ctx<TAB>cram<TAB>mmproj_file
    models.py whitelist  <machine>   newline list of every GGUF filename (model + mmproj)
    models.py path                   the resolved models.json path being used (debugging)
"""
import json
import os
import sys
from pathlib import Path


def resolve_models_json(explicit=None):
    """The file this session's bash/python callers should read, in priority order."""
    if explicit:
        return Path(explicit)
    env = os.environ.get('IK_LLAMA_MODELS_JSON')
    if env:
        return Path(env)
    here = Path(__file__).resolve().parent.parent   # llm/: models.json sits above shared/
    local = here / 'models.local.json'
    if local.is_file():
        return local
    return here / 'models.json'


def load_data(explicit=None):
    path = resolve_models_json(explicit)
    with open(path) as f:
        return json.load(f)


def load_modes(machine, explicit=None):
    """The raw list of mode dicts for one machine, exactly as stored in the JSON."""
    return load_data(explicit).get('machines', {}).get(machine, [])


def _downloadable_rows(mode):
    rows = [(mode['file'], mode['download'])]
    if mode.get('mmproj'):
        rows.append((mode['mmproj']['file'], mode['mmproj']))
    return rows


def _cli_modes(machine):
    for m in load_modes(machine):
        mmproj = (m.get('mmproj') or {}).get('file') or ''
        fields = [
            m['desc'], m['file'], str(m['ctx']), str(m['cram']),
            'YARN' if m.get('yarn') else '',
            'SAMPLE' if m.get('sample') else '',
            mmproj,
            m.get('spec') or '',
            'CT' if m.get('chat_template') else '',
        ]
        print('|'.join(fields))


def _cli_downloads(machine):
    for mode in load_modes(machine):
        for local_name, d in _downloadable_rows(mode):
            bytes_ = d.get('bytes')
            print('\t'.join([local_name, d['repo'], d['repo_file'], '' if bytes_ is None else str(bytes_)]))


def _cli_info(machine):
    for mode in load_modes(machine):
        mmproj = (mode.get('mmproj') or {}).get('file', '')
        print('\t'.join([mode['desc'], mode['file'], str(mode['ctx']), str(mode['cram']), mmproj]))


def _cli_whitelist(machine):
    files = set()
    for mode in load_modes(machine):
        files.add(mode['file'])
        if mode.get('mmproj'):
            files.add(mode['mmproj']['file'])
    for f in sorted(files):
        print(f)


def _cli_path():
    print(resolve_models_json())


_SUBCOMMANDS = {
    'modes': _cli_modes,
    'downloads': _cli_downloads,
    'info': _cli_info,
    'whitelist': _cli_whitelist,
}


def main(argv):
    if not argv:
        print(__doc__, file=sys.stderr)
        return 1
    cmd, rest = argv[0], argv[1:]
    if cmd == 'path':
        _cli_path()
        return 0
    fn = _SUBCOMMANDS.get(cmd)
    if not fn:
        print(f"Unknown subcommand: {cmd}. See models.py --help.", file=sys.stderr)
        return 1
    if not rest:
        print(f"Usage: models.py {cmd} <machine>", file=sys.stderr)
        return 1
    fn(rest[0])
    return 0


if __name__ == '__main__':
    if '--help' in sys.argv or '-h' in sys.argv:
        print(__doc__)
        sys.exit(0)
    sys.exit(main(sys.argv[1:]))
