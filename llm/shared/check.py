#!/usr/bin/env python3
"""Check the repository without touching any real engine, model or agent config.

    llm/check.sh            (or: python3 llm/shared/check.py)      exit 0 = all passed

Static, everywhere (laptop, i9, CI):
  - every *.sh parses (bash -n); every *.py compiles; every *.ps1 parses (only where pwsh exists)
  - models.json (and the example): valid JSON, required fields per machine, unique ids
  - the public-repo rule: no internal hostnames, private addresses or key file names in tracked files
Dry runs in a throwaway sandbox (fake HOME, fake model files, a fake server that only echoes its argv,
a fake Ollama answering /api/tags):
  - i9: start.sh prints a server command for every mode, with thinking off; the llama-swap config
    parses and each model's cmd, split the way llama-swap splits it, starts the (fake) server
  - mac: the llama-swap config parses, carries the thinking-off filter and a readable name per model
  - agent setup for i9, mac and probook writes the expected provider and models (dry run, then real
    into the fake HOME)
On a known machine (models.detect_machine) it also checks THIS machine, still read-only: the engine and
llama-swap binaries, which catalog models are on disk, and `llama-swap -validate` on the config that
llama-swap-setup would write (written to a temp file, not to ~/.config).
"""
import http.server
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import threading
from pathlib import Path

LLM = Path(__file__).resolve().parent.parent
REPO = LLM.parent
SHARED = LLM / 'shared'
sys.path.insert(0, str(SHARED))
import models  # noqa: E402

FAILS, NOTES = [], []


def ok(msg):
    print(f'  ok    {msg}')


def fail(msg):
    FAILS.append(msg)
    print(f'  FAIL  {msg}')


def note(msg):
    NOTES.append(msg)
    print(f'  skip  {msg}')


def find_bin(name):
    """Same lookup as shared/common.sh find_bin: PATH, then the brew prefixes."""
    for c in (shutil.which(name), f'/home/linuxbrew/.linuxbrew/bin/{name}', f'/opt/homebrew/bin/{name}',
              f'/usr/local/bin/{name}'):
        if c and os.access(c, os.X_OK):
            return c
    return None


def run(argv, env=None, **kw):
    return subprocess.run(argv, capture_output=True, text=True, env={**os.environ, **(env or {})}, **kw)


def tracked(pattern):
    out = run(['git', '-C', str(REPO), 'ls-files', pattern]).stdout.split()
    return [REPO / p for p in out] or sorted(REPO.glob('**/' + pattern))


# ── static ──────────────────────────────────────────────────────────────────

def check_syntax():
    print('syntax')
    for f in tracked('*.sh'):
        r = run(['bash', '-n', str(f)])
        (ok if r.returncode == 0 else fail)(f'bash -n {f.relative_to(REPO)}' + ('' if r.returncode == 0 else f': {r.stderr.strip()[:200]}'))
    bad = [f for f in tracked('*.py') if run([sys.executable, '-m', 'py_compile', str(f)]).returncode != 0]
    for f in bad:
        fail(f'py_compile {f.relative_to(REPO)}')
    if not bad:
        ok(f'py_compile: {len(tracked("*.py"))} files')
    pwsh = shutil.which('pwsh')
    if not pwsh:
        note('PowerShell parse: pwsh not installed here (CI runs it)')
        return
    files = [str(f) for f in tracked('*.ps1')]
    script = ('$bad=0; foreach ($f in $args) { $t=$null; $e=$null; '
              '[System.Management.Automation.Language.Parser]::ParseFile($f,[ref]$t,[ref]$e) | Out-Null; '
              'foreach ($x in $e) { Write-Output ("$f" + ": " + $x.Message); $bad++ } }; exit $bad')
    r = run([pwsh, '-NoProfile', '-Command', script, *files])
    (ok if r.returncode == 0 else fail)(f'PowerShell parse: {len(files)} files' + ('' if r.returncode == 0 else '\n' + r.stdout))


REQUIRED = {'i9': ('name', 'file', 'ctx', 'download'), 'probook': ('name', 'short', 'file', 'ctx', 'engine'),
            'mac': ('name', 'id', 'ollama', 'ctx')}
ID_KEY = {'i9': 'file', 'probook': 'short', 'mac': 'id'}


def check_catalog():
    print('catalog')
    for path in (LLM / 'models.json', LLM / 'models.local.json.example'):
        try:
            data = json.loads(path.read_text(encoding='utf-8'))
        except ValueError as e:
            fail(f'{path.name}: not valid JSON ({e})')
            continue
        for machine, entries in data.get('machines', {}).items():
            if machine not in REQUIRED:
                fail(f'{path.name}: unknown machine "{machine}" (expected {", ".join(REQUIRED)})')
                continue
            ids = []
            for i, m in enumerate(entries):
                missing = [k for k in REQUIRED[machine] if k not in m]
                if missing:
                    fail(f'{path.name}: {machine}[{i}] lacks {", ".join(missing)}')
                if machine in ('i9', 'probook') and not str(m.get('file', '')).endswith('.gguf'):
                    fail(f'{path.name}: {machine}[{i}] file is not a .gguf')
                if machine == 'i9' and not isinstance((m.get('download') or {}).get('bytes'), int):
                    fail(f'{path.name}: {machine}[{i}] download.bytes is not pinned (download-models.sh verifies it)')
                if machine == 'probook' and m.get('engine') not in ('mainline', 'ik_llama'):
                    fail(f'{path.name}: {machine}[{i}] engine must be mainline or ik_llama')
                ids.append(m.get(ID_KEY[machine]))
            dup = {x for x in ids if ids.count(x) > 1}
            if dup:
                fail(f'{path.name}: {machine} ids not unique: {", ".join(map(str, dup))}')
        ok(f'{path.name}: {", ".join(f"{k} {len(v)}" for k, v in data.get("machines", {}).items())}')


# Real internal values only: placeholders such as ~/.ssh/<key> or <user>@<host> are fine.
LEAKS = re.compile(r'pmon-[a-z]|\b192\.168\.\d|\b10\.\d+\.\d+\.\d+\b|\.ssh/[A-Za-z0-9_.-]+_(rsa|ed25519|ecdsa)\b|elitebook')


def check_public():
    print('public-repo rule')
    hits = []
    for f in tracked('*'):
        if f.suffix in ('.png', '.jpg', '.gguf', '.pyc') or not f.is_file():
            continue
        try:
            for n, line in enumerate(f.read_text(encoding='utf-8', errors='ignore').splitlines(), 1):
                if LEAKS.search(line):
                    hits.append(f'{f.relative_to(REPO)}:{n}')
        except OSError:
            pass
    if hits:
        fail('internal hostname/address/key name in: ' + ', '.join(hits[:10]))
    else:
        ok('no internal hostnames, private addresses or key file names')


# ── dry runs in a sandbox ───────────────────────────────────────────────────

class FakeOllama(http.server.BaseHTTPRequestHandler):
    names = []

    def do_GET(self):
        body = json.dumps({'models': [{'name': n + ':latest'} for n in self.names]}).encode()
        self.send_response(200)
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


def sandbox():
    sb = Path(tempfile.mkdtemp(prefix='llm-check.'))
    home = sb / 'home'
    root = home / '.local' / 'share' / 'llama.cpp'
    for d in ('models', 'ik_llama/build/bin', 'llama.cpp-cpu'):
        (root / d).mkdir(parents=True)
    for d in ('.config/opencode', '.pi/agent'):
        (home / d).mkdir(parents=True)
    server = root / 'ik_llama' / 'build' / 'bin' / 'llama-server'
    server.write_text('#!/bin/sh\necho "FAKE-SERVER $*"\n')
    server.chmod(0o755)
    (root / 'llama.cpp-cpu' / 'llama-server.exe').write_text('')
    for machine in ('i9', 'probook'):
        for m in models.load_modes(machine):
            (root / 'models' / m['file']).write_text('')
    env = {'HOME': str(home), 'LLM_ROOT': str(root), 'MODELS_DIR': str(root / 'models'),
           'IK_LLAMA_DIR': str(root / 'ik_llama'), 'XDG_CONFIG_HOME': str(home / '.config'),
           'XDG_DATA_HOME': str(home / '.local' / 'share')}
    return sb, env


def check_i9(env):
    print('i9 dry run')
    for m in models.load_modes('i9'):
        mid = m['file'][:-len('.gguf')]
        r = run(['bash', str(LLM / 'i9' / 'start.sh'), mid], env={**env, 'IK_LLAMA_PRINT_CMD': '1'})
        line = r.stdout.strip()
        if r.returncode == 0 and line.startswith('exec ') and ' -rea off' in line and m['file'] in line:
            ok(f'start.sh prints the server command for {mid} (thinking off)')
        else:
            fail(f'start.sh {mid}: rc={r.returncode} {(r.stderr or line)[:200]}')
    r = run([sys.executable, str(SHARED / 'llama_swap_config.py'), '--machine', 'i9'], env=env)
    if r.returncode != 0:
        fail(f'llama_swap_config.py i9: {r.stderr.strip()[:200]}')
        return
    cfg = load_yaml(r.stdout, 'i9 llama-swap config')
    for mid, m in (cfg or {}).get('models', {}).items():
        argv = shlex.split(m['cmd'].replace('${PORT}', '5999'))
        out = run(argv, env=env)
        if out.returncode == 0 and 'FAKE-SERVER' in out.stdout and '--port 5999' in out.stdout:
            ok(f'llama-swap cmd for {mid} starts the server it names, on llama-swap\'s port')
        else:
            fail(f'llama-swap cmd for {mid}: rc={out.returncode} {(out.stderr or out.stdout)[:200]}')
        if not m.get('name'):
            fail(f'llama-swap entry {mid} has no readable name')


def load_yaml(text, what):
    try:
        import yaml
    except ImportError:
        note(f'{what}: PyYAML not installed, not parsed')
        return None
    try:
        data = yaml.safe_load(text)
        ok(f'{what} parses')
        return data
    except Exception as e:
        fail(f'{what} does not parse: {e}')
        return None


def check_mac(env, port):
    print('mac dry run')
    r = run([sys.executable, str(SHARED / 'llama_swap_config.py'), '--machine', 'mac'],
            env={**env, 'OLLAMA_HOST_PORT': str(port)})
    if r.returncode != 0:
        fail(f'llama_swap_config.py mac: {r.stderr.strip()[:200]}')
        return
    if 'reasoning_effort: none' in r.stdout and 'type: disabled' in r.stdout:
        ok('mac config turns thinking off for both API formats')
    else:
        fail('mac config lacks the thinking-off filter')
    cfg = load_yaml(r.stdout, 'mac llama-swap config')
    if cfg:
        names = {k: v.get('name') for k, v in (cfg.get('selectors') or {}).items()}
        want = {m['id'] for m in models.load_modes('mac')}
        (ok if set(names) == want and all(names.values()) else fail)(f'mac selectors with readable names: {sorted(names)}')


def check_agents(env, port):
    print('agent setup dry run')
    expect = {'i9': 'ik-llama', 'mac': 'ollama', 'probook': 'llamacpp'}
    for machine, provider in expect.items():
        e = {**env, 'OLLAMA_HOST_PORT': str(port)}
        dry = run([sys.executable, str(SHARED / 'setup_agents.py'), '--machine', machine, '--dry-run'], env=e)
        real = run([sys.executable, str(SHARED / 'setup_agents.py'), '--machine', machine], env=e)
        try:
            oc = json.loads((Path(env['XDG_CONFIG_HOME']) / 'opencode' / 'opencode.json').read_text())
            got = oc['provider'][provider]
            good = (dry.returncode == 0 and real.returncode == 0 and got['options']['baseURL'].endswith(':9081/v1')
                    and got['models'] and all(v.get('name') for v in got['models'].values()))
        except (OSError, KeyError, ValueError) as ex:
            good, got = False, ex
        (ok if good else fail)(f'setup_agents {machine}: provider {provider} -> 9081, '
                               f'{len(got["models"]) if good else 0} models'
                               + ('' if good else f' ({dry.stderr.strip()[:120]} {real.stderr.strip()[:120]} {got})'))


# ── this machine (read-only) ────────────────────────────────────────────────

def check_this_machine():
    machine = models.detect_machine()
    print(f'this machine: {machine or "unknown (CI or another host) - skipped"}')
    if not machine or machine == 'probook':
        if machine == 'probook':
            note('ProBook: run llm\\probook\\start-llm.ps1 -ListOnly and llama-swap-setup.ps1 -WhatIf')
        return
    swap = find_bin('llama-swap')
    (ok if swap else fail)(f'llama-swap binary: {swap or "not found (../tools/llama-swap-install.sh)"}')
    if machine == 'i9':
        server = Path(os.environ.get('IK_LLAMA_DIR') or models.LLAMA_ROOT / 'ik_llama') / 'build' / 'bin' / 'llama-server'
        (ok if os.access(server, os.X_OK) else fail)(f'ik_llama server: {server}')
        mdir = Path(os.environ.get('MODELS_DIR') or models.LLAMA_ROOT / 'models')
        for m in models.load_modes('i9'):
            p = mdir / m['file']
            if p.is_file():
                size = p.stat().st_size
                want = (m.get('download') or {}).get('bytes')
                (ok if size == want else fail)(f'{m["file"]}: on disk, {size} bytes' + ('' if size == want else f' (catalog says {want})'))
            else:
                note(f'{m["file"]}: not on disk (./i9/download-models.sh fetches it)')
    else:
        (ok if find_bin('ollama') else fail)('ollama binary')
    r = run([sys.executable, str(SHARED / 'llama_swap_config.py'), '--machine', machine])
    if r.returncode != 0:
        fail(f'llama-swap config for this machine: {r.stderr.strip()[:200]}')
    elif swap:
        with tempfile.NamedTemporaryFile('w', suffix='.yaml', delete=False) as t:
            t.write(r.stdout)
        v = run([swap, '-config', t.name, '-validate'])
        os.unlink(t.name)
        (ok if v.returncode == 0 else fail)(f'llama-swap -validate: {(v.stdout or v.stderr).strip()[:150]}')
    a = run([sys.executable, str(SHARED / 'setup_agents.py'), '--machine', machine, '--dry-run'])
    (ok if a.returncode == 0 else fail)('agent setup dry run on the real HOME' + ('' if a.returncode == 0 else f': {a.stderr.strip()[:200]}'))


def main():
    check_syntax()
    check_catalog()
    check_public()
    sb, env = sandbox()
    FakeOllama.names = [m.get('ollama', '') for m in models.load_modes('mac')]
    srv = http.server.HTTPServer(('127.0.0.1', 0), FakeOllama)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    try:
        check_i9(env)
        check_mac(env, srv.server_port)
        check_agents(env, srv.server_port)
    finally:
        srv.shutdown()
        shutil.rmtree(sb, ignore_errors=True)
    check_this_machine()
    print()
    if FAILS:
        print(f'FAILED: {len(FAILS)} check(s)')
        sys.exit(1)
    print(f'all checks passed ({len(NOTES)} skipped)')


if __name__ == '__main__':
    main()
