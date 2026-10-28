#!/usr/bin/env python3
"""Write the local-model provider into every installed agent's config, on any of the three machines.

One codebase for the i9, the Mac and the ProBook; the entry points are llm/setup-agents.sh (i9, Mac)
and llm/probook/setup-agents.ps1 (ProBook), which only call this file.

    setup_agents.py [--machine i9|mac|probook] [--dry-run] [--base-url URL]

The machine comes from --machine, else $LLM_MACHINE, else is detected (macOS -> mac, Windows ->
probook, Linux with an ik_llama install -> i9). Anything else refuses to run, so a config meant for
one machine cannot land on another.

Models come from llm/models.json (models.local.json if present) and only those actually available are
written: i9 = GGUF on disk, probook = GGUF and its engine's llama-server.exe, mac = model known to
Ollama. Agents default to the llama-swap chain, http://127.0.0.1:9081/v1 (local-proxy -> llama-swap).

Agents configured, each only when installed (binary on PATH or its config directory exists):
OpenCode (provider + compaction, auth entry), Pi (provider), Docker Agent (provider base_url, plus API
keys synced from ~/.secrets). References to models that are no longer served (OpenCode model,
small_model and per-agent models, Pi defaultModel, Docker Agent default_model) are removed. Every file
is validated before anything is written, and an existing file is backed up as <file>.bak first.
"""
import argparse
import json
import os
import re
import shutil
import stat
import sys
import tempfile
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from models import LLAMA_ROOT, MACHINES, detect_machine, load_modes, resolve_models_json  # noqa: E402

HOME = Path.home()
DEFAULT_BASE_URL = 'http://127.0.0.1:9081/v1'
OUTPUT_LIMIT = int(os.environ.get('OPENCODE_OUTPUT_LIMIT', '8192'))
COMPACTION_RESERVED = int(os.environ.get('OPENCODE_COMPACTION_RESERVED', '10000'))

# Provider ids are part of every agent config already written: never rename them here.
PROVIDER = {'i9': 'ik-llama', 'mac': 'ollama', 'probook': 'llamacpp'}


class ConfigError(Exception):
    pass


# ── which models are actually available ──────────────────────────────────────

def models_for(machine):
    """[(id, display name, context, vision)] for the models this machine can serve right now."""
    models_dir = Path(os.environ.get('MODELS_DIR') or LLAMA_ROOT / 'models')
    ctx_override = os.environ.get('IK_LLAMA_CTX_SIZE')
    out = []
    if machine == 'i9':
        for m in load_modes('i9'):
            if (models_dir / m['file']).is_file():
                out.append((m['file'][:-len('.gguf')], m.get('name') or m['file'], int(ctx_override or m['ctx']),
                            bool(m.get('mmproj'))))
    elif machine == 'probook':
        engine_dir = {'mainline': LLAMA_ROOT / 'llama.cpp-cpu', 'ik_llama': LLAMA_ROOT / 'ik_llama'}
        for m in load_modes('probook'):
            exe = engine_dir.get(m.get('engine'), Path('-')) / 'llama-server.exe'
            if (models_dir / m['file']).is_file() and exe.is_file():
                out.append((m['short'], m.get('name') or m['file'], int(m['ctx']), bool(m.get('mmproj'))))
            else:
                print(f"  - {m['short']}: skipped (model and/or its engine not present)")
    elif machine == 'mac':
        port = os.environ.get('OLLAMA_HOST_PORT', '11434')
        try:
            with urllib.request.urlopen(f'http://127.0.0.1:{port}/api/tags', timeout=5) as r:
                have = {t['name'].removesuffix(':latest') for t in json.load(r)['models']}
        except OSError:
            have = None
            print(f'Note: Ollama is not answering on {port}; writing every mac model from the catalog.')
        for m in load_modes('mac'):
            if have is None or m['ollama'] in have:
                out.append((m['ollama'], m.get('name') or m['ollama'], int(m['ctx']), False))
            else:
                print(f"  - {m['ollama']}: skipped (not in Ollama; ollama pull {m.get('source', '')})")
    return out


# ── config file helpers ──────────────────────────────────────────────────────

def installed(binary, config_dir):
    return shutil.which(binary) is not None or config_dir.exists()


def load_json(path):
    """Existing JSON object, or {} when the file is absent. Anything else aborts the whole run.
    utf-8-sig: Windows tools often write a byte-order mark, which plain utf-8 JSON parsing rejects."""
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding='utf-8-sig'))
    except ValueError as e:
        raise ConfigError(f'{path}: not valid JSON ({e}); comments (JSONC) are not supported')
    if not isinstance(data, dict):
        raise ConfigError(f'{path}: expected a JSON object at the top level')
    return data


def need_dict(parent, key, path):
    """parent[key] as a dict (created when missing or null); any other type aborts."""
    val = parent.get(key)
    if val is None:
        val = parent[key] = {}
    if not isinstance(val, dict):
        raise ConfigError(f'{path}: "{key}" is {type(val).__name__}, expected an object')
    return val


def atomic_write(path, content, dry, mode=None):
    if dry:
        print(f'[dry-run] would write {path}')
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        shutil.copy2(path, path.with_name(path.name + '.bak'))
    fd, tmp = tempfile.mkstemp(prefix=f'.{path.name}.tmp.', dir=str(path.parent))
    try:
        if mode is not None and hasattr(os, 'fchmod'):
            os.fchmod(fd, mode)
        with os.fdopen(fd, 'wb') as f:
            f.write(content.encode('utf-8'))
        os.replace(tmp, path)
        if mode is not None and os.name != 'nt':
            os.chmod(path, mode)
        print(f'Wrote {path}')
    except Exception:
        if os.path.exists(tmp):
            try:
                os.unlink(tmp)
            except OSError:
                pass
        raise


def read_secrets(path):
    secrets = {}
    for line in path.read_text(encoding='utf-8-sig').splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        m = re.match(r'^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$', line)
        if not m:
            continue
        k, raw = m.group(1), m.group(2).strip()
        if (raw.startswith('"') and raw.endswith('"')) or (raw.startswith("'") and raw.endswith("'")):
            val = raw[1:-1]
        elif raw.startswith('"') or raw.startswith("'"):
            print(f'Warning: {path}: key {k} has an unmatched quote (multiline values not supported); skipping',
                  file=sys.stderr)
            continue
        else:
            val = raw.split('#', 1)[0].strip()
        if re.search(r'[\r\n\x00-\x1f]', val):
            print(f'Warning: {path}: key {k} contains control characters; skipping', file=sys.stderr)
            continue
        secrets[k] = val
    return secrets


# ── main ─────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--machine', choices=MACHINES)
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--base-url', default=os.environ.get('AGENT_BASE_URL', DEFAULT_BASE_URL),
                    help=f'agent-facing URL (default {DEFAULT_BASE_URL}, the llama-swap chain)')
    args = ap.parse_args()

    machine = args.machine or detect_machine()
    if machine not in PROVIDER:
        sys.exit('Cannot tell which machine this is; pass --machine i9|mac|probook (or set LLM_MACHINE).')
    provider, base_url, dry = PROVIDER[machine], args.base_url, args.dry_run
    print(f'setup-agents: machine={machine} provider={provider} url={base_url} catalog={resolve_models_json()}')

    models = models_for(machine)
    if not models:
        sys.exit(f'No model of machine "{machine}" is available here; nothing to configure '
                 '(see llm/README.md, first setup).')
    valid = {mid for mid, _, _, _ in models}

    opencode_dir = Path(os.environ.get('XDG_CONFIG_HOME') or HOME / '.config') / 'opencode'
    opencode_config = opencode_dir / 'opencode.json'
    opencode_auth = Path(os.environ.get('XDG_DATA_HOME') or HOME / '.local' / 'share') / 'opencode' / 'auth.json'
    pi_dir = HOME / '.pi' / 'agent'
    cagent_dir = Path(os.environ.get('XDG_CONFIG_HOME') or HOME / '.config') / 'cagent'
    secrets_file = HOME / '.secrets'

    has_opencode = installed('opencode', opencode_dir)
    has_pi = installed('pi', pi_dir)
    has_cagent = bool(shutil.which('docker-agent') or shutil.which('cagent') or cagent_dir.exists())

    opencode_models, pi_models = {}, []
    for mid, name, ctx, vision in models:
        oc_model = {'name': name, 'limit': {'context': ctx, 'output': OUTPUT_LIMIT}}
        pi_model = {'id': mid, 'name': name, 'contextWindow': ctx, 'maxTokens': OUTPUT_LIMIT,
                    # thinking is off on every machine (server flags, or llama-swap on the Mac)
                    'reasoning': False}
        if vision:
            oc_model['modalities'] = {'input': ['text', 'image'], 'output': ['text']}
            pi_model['attachment'] = True
            pi_model['input'] = ['text', 'image']
        opencode_models[mid] = oc_model
        pi_models.append(pi_model)

    removed, writes = [], []

    def stale_ref(ref):
        """True for a '<provider>/<id>' reference whose model is no longer served."""
        return isinstance(ref, str) and ref.startswith(provider + '/') and ref.split('/', 1)[1] not in valid

    try:
        # phase 1+2: load and validate everything, compute the new state in memory
        if has_opencode:
            oc = load_json(opencode_config)
            auth = load_json(opencode_auth)
            providers = need_dict(oc, 'provider', opencode_config)
            old = providers.get(provider)
            if old is not None and not isinstance(old, dict):
                raise ConfigError(f'{opencode_config}: provider.{provider} is not an object')
            for gone in sorted(set((old or {}).get('models') or {}) - valid):
                removed.append(f'OpenCode provider model: {gone}')
            providers[provider] = {'npm': '@ai-sdk/openai-compatible', 'name': provider,
                                   'options': {'baseURL': base_url, 'apiKey': 'dummy'}, 'models': opencode_models}
            oc['compaction'] = {'auto': True, 'prune': True, 'reserved': COMPACTION_RESERVED}
            for key in ('model', 'small_model'):
                if stale_ref(oc.get(key)):
                    removed.append(f'OpenCode {key}: {oc[key]}')
                    del oc[key]
            for aname, agent in (need_dict(oc, 'agent', opencode_config) if 'agent' in oc else {}).items():
                if isinstance(agent, dict):
                    for key in ('model', 'small_model'):
                        if stale_ref(agent.get(key)):
                            removed.append(f'OpenCode agent "{aname}" {key}: {agent[key]}')
                            del agent[key]
            writes.append((opencode_config, json.dumps(oc, indent=2) + '\n', None))
            if provider not in auth:
                auth[provider] = {'type': 'api', 'key': 'dummy'}
                writes.append((opencode_auth, json.dumps(auth, indent=2) + '\n', None))

        if has_pi:
            pi_config, pi_settings = pi_dir / 'models.json', pi_dir / 'settings.json'
            pi = load_json(pi_config)
            st = load_json(pi_settings)
            pi_providers = need_dict(pi, 'providers', pi_config)
            old = pi_providers.get(provider)
            if old is not None and (not isinstance(old, dict) or not isinstance(old.get('models', []), list)):
                raise ConfigError(f'{pi_config}: providers.{provider}.models is not a list')
            old_ids = {m.get('id') for m in (old or {}).get('models', []) if isinstance(m, dict)}
            for gone in sorted(x for x in old_ids - valid if x):
                removed.append(f'Pi provider model: {gone}')
            pi_providers[provider] = {'baseUrl': base_url, 'api': 'openai-completions', 'apiKey': 'dummy',
                                      'compat': {'supportsDeveloperRole': False, 'supportsReasoningEffort': False},
                                      'models': pi_models}
            writes.append((pi_config, json.dumps(pi, indent=2) + '\n', None))
            if st.get('defaultProvider') == provider and 'defaultModel' in st and st['defaultModel'] not in valid:
                removed.append(f'Pi defaultModel: {st["defaultModel"]} (choose a new one with /model)')
                del st['defaultModel']
                writes.append((pi_settings, json.dumps(st, indent=2) + '\n', None))

        cagent_on = False
        if has_cagent:
            cagent_on = configure_cagent(cagent_dir, provider, base_url, stale_ref, removed, writes)
            if secrets_file.exists():
                sync_cagent_env(cagent_dir / '.env', read_secrets(secrets_file), writes, dry)
    except ConfigError as e:
        sys.exit(f'Refusing to change anything: {e}')

    # phase 3: write
    for path, content, mode in writes:
        atomic_write(path, content, dry, mode)

    print()
    if removed:
        print('Stale settings ' + ('that would be removed:' if dry else 'removed:'))
        for r in removed:
            print(f'  - {r}')
    else:
        print('No stale settings found.')
    configured = [n for n, on in (('OpenCode', has_opencode), ('Pi', has_pi), ('Docker Agent', cagent_on)) if on]
    print(f'Configured: {", ".join(configured) or "no agent installed"}')
    print(f'Models (use as {provider}/<id>):')
    for mid, name, _, _ in models:
        print(f'  {provider}/{mid}   {name}')
    print(f'Limits: output={OUTPUT_LIMIT}, compaction reserved={COMPACTION_RESERVED}')


def configure_cagent(cagent_dir, provider, base_url, stale_ref, removed, writes):
    """Docker Agent's config.yaml: provider base_url and a stale default_model. False when skipped."""
    try:
        import yaml
    except ImportError:
        print('Warning: PyYAML not installed; skipping Docker Agent', file=sys.stderr)
        return False
    path = cagent_dir / 'config.yaml'
    data = {}
    if path.exists():
        try:
            data = yaml.safe_load(path.read_text(encoding='utf-8-sig')) or {}
        except Exception as e:
            print(f'Warning: failed to parse {path} ({e}); skipping Docker Agent', file=sys.stderr)
            return False
        if not isinstance(data, dict):
            print(f'Warning: {path} is not a YAML mapping; skipping Docker Agent', file=sys.stderr)
            return False
    providers = data.setdefault('providers', {})
    if not isinstance(providers, dict):
        print(f"Warning: {path}: 'providers' is not a mapping; skipping Docker Agent", file=sys.stderr)
        return False
    prov = providers.get(provider)
    if not isinstance(prov, dict):
        prov = providers[provider] = {}
    changed = not path.exists()
    if prov.get('base_url') != base_url:
        prov['base_url'] = base_url
        changed = True
    if stale_ref(data.get('default_model')):
        removed.append(f'Docker Agent default_model: {data["default_model"]}')
        del data['default_model']
        changed = True
    if changed:
        writes.append((path, yaml.dump(data, sort_keys=False), None))
    return True


def sync_cagent_env(env_path, secrets, writes, dry):
    """Copy the cloud API keys Docker Agent needs from ~/.secrets into its .env (mode 0600)."""
    want = {}
    oc_key = secrets.get('OPENCODE_API_KEY') or secrets.get('OPENCODE_GO_API_KEY')
    if oc_key:
        want['OPENCODE_API_KEY'] = oc_key
    for k in ('OPENROUTER_API_KEY', 'NVIDIA_API_KEY'):
        if k in secrets:
            want[k] = secrets[k]
    lines = env_path.read_text(encoding='utf-8-sig').splitlines() if env_path.exists() else []
    seen, out, changed = set(), [], False
    for line in lines:
        m = re.match(r'^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$', line.strip())
        if m and m.group(1) in want:
            k, cur = m.group(1), m.group(2).strip()
            if len(cur) >= 2 and cur[0] == cur[-1] and cur[0] in '"\'':
                cur = cur[1:-1]
            seen.add(k)
            if cur != want[k]:
                out.append(f'{k}={want[k]}')
                changed = True
                continue
        out.append(line)
    for k, v in want.items():
        if k not in seen:
            if not out:
                out.append('# docker-agent environment variables')
            out.append(f'{k}={v}')
            changed = True
    if changed:
        writes.append((env_path, '\n'.join(out) + '\n', 0o600))
    elif env_path.exists() and os.name != 'nt' and stat.S_IMODE(env_path.stat().st_mode) != 0o600:
        if dry:
            print(f'[dry-run] would fix permissions on {env_path}')
        else:
            env_path.chmod(0o600)
            print(f'Fixed permissions on {env_path} to 0600')


if __name__ == '__main__':
    main()
