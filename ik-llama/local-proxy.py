#!/usr/bin/env python3
"""
local-proxy.py — thin HTTP proxy for llama-server.
Caps max_tokens in /v1/messages requests to avoid "exceeds context size" errors.
Claude CLI always sends max_tokens=32000; local models often have smaller budgets.

Env vars:
  LOCAL_PROXY_PORT        Proxy listen port          (default: 9081)
  LOCAL_PROXY_UPSTREAM    Upstream llama-server URL  (default: http://127.0.0.1:9080)
  LOCAL_PROXY_MAX_TOKENS  max_tokens cap             (default: 16384)
"""
import http.client
import http.server
import json
import os
import queue
import sys
import threading
from urllib.parse import urlparse

PROXY_PORT = int(os.environ.get("LOCAL_PROXY_PORT", "9081"))
UPSTREAM = os.environ.get("LOCAL_PROXY_UPSTREAM", "http://127.0.0.1:9080")
MAX_TOKENS_CAP = int(os.environ.get("LOCAL_PROXY_MAX_TOKENS", "16384"))
# Cold prefill on CPU can run minutes with zero bytes from upstream. Without a
# keep-alive, Claude Code's idle-read timeout fires intermittently ("API
# timeout") well before our own 3600s socket timeout. SSE comment lines
# (leading ":") are inert per spec — any Anthropic-compatible SSE parser
# ignores them — so send one periodically while waiting for upstream data.
KEEPALIVE_SECS = float(os.environ.get("LOCAL_PROXY_KEEPALIVE_SECS", "10"))

_up = urlparse(UPSTREAM)
UPSTREAM_HOST = _up.hostname or "127.0.0.1"
UPSTREAM_PORT = _up.port or 9080

_SKIP_REQ_HEADERS = {"host", "content-length", "transfer-encoding"}
_SKIP_RESP_HEADERS = {"transfer-encoding", "connection"}


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # suppress per-request stdout noise

    def _read_body(self):
        length = self.headers.get("Content-Length")
        return self.rfile.read(int(length)) if length else b""

    def _forward(self, body: bytes):
        conn = http.client.HTTPConnection(UPSTREAM_HOST, UPSTREAM_PORT, timeout=3600)
        headers = {k: v for k, v in self.headers.items()
                   if k.lower() not in _SKIP_REQ_HEADERS}
        if body:
            headers["Content-Length"] = str(len(body))
        headers_sent = False
        try:
            conn.request(self.command, self.path, body=body or None, headers=headers)
            resp = conn.getresponse()
            self.send_response(resp.status)
            for k, v in resp.getheaders():
                if k.lower() not in _SKIP_RESP_HEADERS:
                    self.send_header(k, v)
            self.end_headers()
            headers_sent = True
            is_sse = "text/event-stream" in (resp.getheader("Content-Type") or "")

            # Read upstream on a background thread so the main loop can inject
            # keep-alives during gaps (cold prefill) instead of blocking silently.
            # Only safe for SSE: injecting bytes into a plain JSON body would
            # corrupt it, so non-SSE responses fall back to a plain blocking read.
            read_fn = getattr(resp, "read1", resp.read)

            if not is_sse:
                while True:
                    chunk = read_fn(4096)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    self.wfile.flush()
            else:
                chunks: "queue.Queue" = queue.Queue()

                def _reader():
                    try:
                        while True:
                            chunk = read_fn(4096)
                            chunks.put(chunk)
                            if not chunk:
                                return
                    except Exception as exc:
                        chunks.put(exc)

                threading.Thread(target=_reader, daemon=True).start()

                while True:
                    try:
                        item = chunks.get(timeout=KEEPALIVE_SECS)
                    except queue.Empty:
                        self.wfile.write(b":keep-alive\n\n")
                        self.wfile.flush()
                        continue
                    if isinstance(item, Exception):
                        raise item
                    if not item:
                        break
                    self.wfile.write(item)
                    self.wfile.flush()
        except Exception as exc:
            if not headers_sent:
                self.send_error(502, str(exc))
            else:
                sys.stderr.write(f"  stream error after headers sent: {exc}\n")
                sys.stderr.flush()
        finally:
            conn.close()

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/proxy-health":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(f"ok upstream={UPSTREAM_HOST}:{UPSTREAM_PORT} max_tokens_cap={MAX_TOKENS_CAP}".encode())
            return
        self._forward(b"")

    def do_POST(self):
        body = self._read_body()
        parsed = urlparse(self.path)
        if parsed.path == "/v1/messages" and body:
            try:
                data = json.loads(body)
                orig = data.get("max_tokens", 0)
                if orig > MAX_TOKENS_CAP:
                    data["max_tokens"] = MAX_TOKENS_CAP
                    sys.stderr.write(
                        f"[local-proxy] capped max_tokens {orig} → {MAX_TOKENS_CAP}\n"
                    )
                    sys.stderr.flush()
                body = json.dumps(data).encode()
            except Exception as exc:
                sys.stderr.write(f"[local-proxy] body parse error: {exc}\n")
                sys.stderr.flush()
        self._forward(body)


class _QuietServer(http.server.ThreadingHTTPServer):
    def handle_error(self, request, client_address):
        exc = sys.exc_info()[1]
        # Client disconnects mid-stream are normal — don't log tracebacks for them.
        if isinstance(exc, (ConnectionResetError, BrokenPipeError,
                            http.client.RemoteDisconnected)):
            return
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    server = _QuietServer(("127.0.0.1", PROXY_PORT), Handler)
    sys.stderr.write(
        f"[local-proxy] port={PROXY_PORT} upstream={UPSTREAM} max_tokens_cap={MAX_TOKENS_CAP}\n"
    )
    sys.stderr.flush()
    server.serve_forever()
