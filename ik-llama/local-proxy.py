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
import sys
from urllib.parse import urlparse

PROXY_PORT = int(os.environ.get("LOCAL_PROXY_PORT", "9081"))
UPSTREAM = os.environ.get("LOCAL_PROXY_UPSTREAM", "http://127.0.0.1:9080")
MAX_TOKENS_CAP = int(os.environ.get("LOCAL_PROXY_MAX_TOKENS", "16384"))

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
        try:
            conn.request(self.command, self.path, body=body or None, headers=headers)
            resp = conn.getresponse()
        except Exception as exc:
            self.send_error(502, str(exc))
            return

        self.send_response(resp.status)
        for k, v in resp.getheaders():
            if k.lower() not in _SKIP_RESP_HEADERS:
                self.send_header(k, v)
        self.end_headers()

        # Stream response — http.client transparently decodes chunked encoding,
        # so we just forward decoded bytes; BaseHTTPRequestHandler closes on return.
        while True:
            chunk = resp.read(4096)
            if not chunk:
                break
            self.wfile.write(chunk)
            self.wfile.flush()

        conn.close()

    def do_GET(self):
        if self.path == "/proxy-health":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"ok")
            return
        self._forward(b"")

    def do_POST(self):
        body = self._read_body()
        if self.path == "/v1/messages" and body:
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


if __name__ == "__main__":
    server = http.server.ThreadingHTTPServer(("127.0.0.1", PROXY_PORT), Handler)
    sys.stderr.write(
        f"[local-proxy] port={PROXY_PORT} upstream={UPSTREAM} max_tokens_cap={MAX_TOKENS_CAP}\n"
    )
    sys.stderr.flush()
    server.serve_forever()
