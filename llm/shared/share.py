#!/usr/bin/env python3
"""Share this machine's local models with the home gateway through an outgoing SSH tunnel.

    share.py --init        create the tunnel key and the config file, print the gateway's key line
    share.py               open the tunnel and keep it open (foreground; reconnects; Ctrl-C stops sharing)
    share.py --once        one attempt only: exit when the tunnel ends
    share.py --dry-run     print the ssh command instead of running it

llama-swap keeps listening on 127.0.0.1 only. The tunnel is `ssh -R`: the gateway side gets a port that
leads to this machine's 127.0.0.1:9082, and nothing listens here on the network. Away from home the
gateway is unreachable, ssh fails, and nothing is shared.

When the tunnel ends (gateway restarted or updated, laptop asleep, Wi-Fi change) share reconnects after 5 s,
backing off to one try a minute while it keeps failing, until Ctrl-C. Away from home that means one quiet
attempt a minute: stop it there.

Config: ~/.config/llm/share.env (outside the repo; KEY=value lines):
    LLM_SHARE_HOST         the gateway's SSH host (required)
    LLM_SHARE_PORT         its SSH port (default 2222)
    LLM_SHARE_USER         the tunnel user (default llmtunnel)
    LLM_SHARE_REMOTE_PORT  the port this machine gets there (default per machine: mac 19082, probook 19083)
    LLM_SHARE_BIND         the address it binds there (default 0.0.0.0: the gateway's internal network)
Key: ~/.config/llm/share_ed25519, used for nothing else. The gateway only accepts it with
`restrict,port-forwarding,permitlisten="<bind>:<port>"`: no shell, no other port.
"""
import argparse
import os
import shutil
import socket
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from models import detect_machine  # noqa: E402

CONFIG_DIR = Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config') / 'llm'
CONFIG = CONFIG_DIR / 'share.env'
KEY = CONFIG_DIR / 'share_ed25519'
LOCAL_PORT = int(os.environ.get('LLAMA_SWAP_PORT', '9082'))
REMOTE_PORT = {'mac': 19082, 'probook': 19083}


def read_config():
    cfg = {}
    if CONFIG.exists():
        for line in CONFIG.read_text(encoding='utf-8-sig').splitlines():
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                k, v = line.split('=', 1)
                cfg[k.strip()] = v.strip().strip('"\'')
    machine = detect_machine()
    cfg.setdefault('LLM_SHARE_PORT', '2222')
    cfg.setdefault('LLM_SHARE_USER', 'llmtunnel')
    cfg.setdefault('LLM_SHARE_BIND', '0.0.0.0')
    if 'LLM_SHARE_REMOTE_PORT' not in cfg and machine in REMOTE_PORT:
        cfg['LLM_SHARE_REMOTE_PORT'] = str(REMOTE_PORT[machine])
    return cfg


def key_line(cfg):
    pub = KEY.with_name(KEY.name + '.pub').read_text().strip()
    return f'restrict,port-forwarding,permitlisten="{cfg["LLM_SHARE_BIND"]}:{cfg["LLM_SHARE_REMOTE_PORT"]}" {pub}'


def init(cfg):
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    if not KEY.exists():
        subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(KEY),
                        '-C', f'llm-share {socket.gethostname()}'], check=True)
        print(f'Created {KEY} (tunnel only; the private key never leaves this machine)')
    else:
        print(f'{KEY} exists, kept')
    if not CONFIG.exists():
        CONFIG.write_text('# llm/shared/share.py: where the home gateway takes the tunnel\n'
                          'LLM_SHARE_HOST=\n'
                          f'LLM_SHARE_PORT={cfg["LLM_SHARE_PORT"]}\n'
                          f'LLM_SHARE_USER={cfg["LLM_SHARE_USER"]}\n'
                          f'LLM_SHARE_REMOTE_PORT={cfg.get("LLM_SHARE_REMOTE_PORT", "")}\n')
        print(f'Created {CONFIG}: fill in LLM_SHARE_HOST')
    if not cfg.get('LLM_SHARE_REMOTE_PORT'):
        sys.exit(f'Set LLM_SHARE_REMOTE_PORT in {CONFIG} (this machine has no default), then run --init again.')
    print('\nAdd this line to the gateway\'s tunnel/authorized_keys:\n')
    print(key_line(cfg))


def ssh_command(cfg):
    return ['ssh', '-N', '-T', '-i', str(KEY), '-p', cfg['LLM_SHARE_PORT'],
            # away from home the gateway does not answer: give up after 10 s, not the ~75 s TCP default
            '-o', 'IdentitiesOnly=yes', '-o', 'ExitOnForwardFailure=yes', '-o', 'ConnectTimeout=10',
            # a dead link (sleep, Wi-Fi change) ends the tunnel within ~30 s instead of hanging
            '-o', 'ServerAliveInterval=10', '-o', 'ServerAliveCountMax=3',
            '-o', 'StrictHostKeyChecking=accept-new',
            '-R', f'{cfg["LLM_SHARE_BIND"]}:{cfg["LLM_SHARE_REMOTE_PORT"]}:127.0.0.1:{LOCAL_PORT}',
            f'{cfg["LLM_SHARE_USER"]}@{cfg["LLM_SHARE_HOST"]}']


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--init', action='store_true')
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--once', action='store_true', help='do not reconnect when the tunnel ends')
    args = ap.parse_args()
    cfg = read_config()
    if args.init:
        return init(cfg)
    missing = [k for k in ('LLM_SHARE_HOST', 'LLM_SHARE_REMOTE_PORT') if not cfg.get(k)]
    if not KEY.exists() or missing:
        sys.exit(f'Not set up: run share --init first' + (f' and set {", ".join(missing)} in {CONFIG}' if missing else ''))
    if not shutil.which('ssh'):
        sys.exit('ssh not found (Windows: the OpenSSH client feature).')
    cmd = ssh_command(cfg)
    if args.dry_run:
        print(' '.join(cmd))
        return
    try:
        urllib.request.urlopen(f'http://127.0.0.1:{LOCAL_PORT}/v1/models', timeout=5).close()
    except OSError as e:
        sys.exit(f'llama-swap is not answering on 127.0.0.1:{LOCAL_PORT} ({e}); start the chain first.')
    print(f'Sharing 127.0.0.1:{LOCAL_PORT} as {cfg["LLM_SHARE_HOST"]}:{cfg["LLM_SHARE_REMOTE_PORT"]} '
          '(gateway side only). Ctrl-C stops.', flush=True)
    wait = 5
    try:
        while True:
            started = time.monotonic()
            rc = subprocess.call(cmd)
            if args.once:
                break
            # a tunnel that held for a while was a good one: start the back-off from the bottom again
            wait = 5 if time.monotonic() - started > 60 else min(wait * 2, 60)
            print(f'{time.strftime("%H:%M:%S")} tunnel ended (ssh exit {rc}): gateway unreachable or link lost; '
                  f'reconnecting in {wait} s (Ctrl-C stops)', flush=True)
            time.sleep(wait)
    except KeyboardInterrupt:
        rc = 0
    print('Tunnel closed.' if rc == 0 else f'Tunnel ended (ssh exit {rc}): gateway unreachable or link lost.')
    sys.exit(rc)


if __name__ == '__main__':
    main()
