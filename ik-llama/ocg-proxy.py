#!/usr/bin/env python3
"""ocg-proxy — Anthropic Messages API → OpenAI Chat Completions bridge for OpenCode Go.

           Claude Code                    OpenCode Go
    Anthropic /v1/messages      OpenAI /v1/chat/completions
    ──────────────────────▶ proxy ──────────────────────────▶
    ◀──────────────────────       ◀──────────────────────────

Zero dependencies, stdlib only. Handles streaming (SSE) and tool use.

Usage:
    export OCG_PROXY_API_KEY=oc-xxxxx
    ./ocg-proxy.py                             # default port 4099

    # Point Claude Code at it:
    ANTHROPIC_BASE_URL=http://localhost:4099 \
    ANTHROPIC_CUSTOM_MODEL_OPTION=deepseek-v4-pro \
    ANTHROPIC_API_KEY=dummy \
    claude --bare --model deepseek-v4-pro

Env vars:
    OCG_PROXY_PORT           Listen port (default 4099)
    OCG_PROXY_UPSTREAM_URL   OpenCode Go base URL (default https://opencode.ai/zen/go/v1)
    OCG_PROXY_API_KEY        OpenCode Go API key (required)
    OCG_PROXY_MODELS         Comma-separated model ids (default: deepseek-v4-pro,kimi-k2.6,glm-4.7)
"""

import json
import os
import re
import ssl
import sys
import time
import uuid
import signal
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse

# ── config ──────────────────────────────────────────────────────────

PORT = int(os.environ.get("OCG_PROXY_PORT", "4099"))
UPSTREAM = os.environ.get("OCG_PROXY_UPSTREAM_URL", "https://opencode.ai/zen/go/v1")
API_KEY = os.environ.get("OCG_PROXY_API_KEY", "")
MODELS = [m.strip() for m in os.environ.get("OCG_PROXY_MODELS",
    "deepseek-v4-pro,kimi-k2.6,glm-4.7").split(",") if m.strip()]


def ssl_context():
    """Build SSL context using system CA certs from env vars (same pattern as
       update.sh/download-models.sh), or skip verification if OCG_PROXY_INSECURE=1."""
    ca_file = os.environ.get("SSL_CERT_FILE") or os.environ.get("REQUESTS_CA_BUNDLE")
    if ca_file and os.path.exists(ca_file):
        return ssl.create_default_context(cafile=ca_file)
    if os.environ.get("OCG_PROXY_INSECURE") == "1":
        return ssl._create_unverified_context()
    return None  # system default (may fail behind corporate proxies)

CTX = ssl_context()
if CTX:
    print(f"ocg-proxy: using custom SSL context (cafile={os.environ.get('SSL_CERT_FILE','') or 'insecure'})",
          file=sys.stderr)

# Cloudflare blocks default Python urllib User-Agent (error 1010)
HEADERS = {
    "Content-Type": "application/json",
    "User-Agent": "Mozilla/5.0 ocg-proxy/1.0"
}


# ── translation helpers ─────────────────────────────────────────────

def anthropic_req_to_openai(req: dict) -> dict:
    """Convert Anthropic Messages request to OpenAI Chat Completions."""
    messages = []

    # System prompt → first message
    system = req.get("system")
    if system:
        if isinstance(system, str):
            messages.append({"role": "system", "content": system})
        elif isinstance(system, list):
            text = "".join(b.get("text", "") for b in system if b.get("type") == "text")
            if text:
                messages.append({"role": "system", "content": text})

    # Messages
    for msg in req.get("messages", []):
        role = msg.get("role", "user")
        content = msg.get("content", "")

        if isinstance(content, str):
            messages.append({"role": role, "content": content})
        elif isinstance(content, list):
            texts = []
            tool_calls = []
            for block in content:
                t = block.get("type", "")
                if t == "text":
                    texts.append(block.get("text", ""))
                elif t == "tool_use":
                    tool_calls.append({
                        "id": block.get("id", ""),
                        "type": "function",
                        "function": {
                            "name": block.get("name", ""),
                            "arguments": json.dumps(block.get("input", {}))
                        }
                    })
                elif t == "tool_result":
                    content_text = block.get("content", "")
                    if isinstance(content_text, list):
                        content_text = "".join(c.get("text", "") for c in content_text if isinstance(c, dict) and c.get("type") == "text")
                    messages.append({
                        "role": "tool",
                        "tool_call_id": block.get("tool_use_id", ""),
                        "content": str(content_text)
                    })
                    continue
            if tool_calls and role == "assistant":
                messages.append({"role": "assistant", "tool_calls": tool_calls})
                if texts:
                    messages[-1]["content"] = "\n".join(texts)
            elif texts:
                messages.append({"role": role, "content": "\n".join(texts)})

    # Build OpenAI request
    body = {
        "model": req.get("model", MODELS[0]),
        "messages": messages,
        "max_tokens": req.get("max_tokens", 4096),
    }

    # Optional fields
    for src, dst in [("temperature", "temperature"), ("top_p", "top_p"),
                     ("top_k", "top_k")]:
        if src in req:
            body[dst] = req[src]

    if "stop_sequences" in req:
        body["stop"] = req["stop_sequences"]

    if "stream" in req:
        body["stream"] = req["stream"]

    # Tools
    tools = req.get("tools") or req.get("functions")  # anthropic-beta: computer-use-2025
    if tools:
        body["tools"] = []
        for t in tools:
            body["tools"].append({
                "type": "function",
                "function": {
                    "name": t.get("name", ""),
                    "description": t.get("description", ""),
                    "parameters": t.get("input_schema", {})
                }
            })
        # Tool choice
        tc = req.get("tool_choice")
        if tc:
            if tc == "auto" or tc == "any":
                body["tool_choice"] = "auto"
            elif isinstance(tc, dict) and tc.get("type") == "tool":
                body["tool_choice"] = {"type": "function", "function": {"name": tc.get("name", "")}}

    return body


def openai_chunk_to_anthropic_events(chunk: dict, model: str, msg_id: str,
                                      state: dict) -> list:
    """Convert one OpenAI SSE chunk to Anthropic SSE events. Returns list of event strings.
       state tracks: {'started': bool, 'block_started': bool, 'tool_idx': int, 'current_tool': str|None}
    """
    events = []
    choice = (chunk.get("choices", [{}]) or [{}])[0]
    delta = choice.get("delta", {})
    finish = choice.get("finish_reason")

    # message_start
    if not state["started"]:
        state["started"] = True
        events.append(f'event: message_start\ndata: {json.dumps({"type":"message_start","message":{"id":msg_id,"type":"message","role":"assistant","content":[],"model":model}})}\n')

    # Tool calls
    tc_delta = delta.get("tool_calls")
    if tc_delta:
        for tc in tc_delta:
            idx = tc.get("index", 0)
            fn = tc.get("function", {})
            tc_id = tc.get("id", "")
            tc_name = fn.get("name", "")
            tc_args = fn.get("arguments", "")

            # content_block_start for this tool
            if idx >= state["tool_idx"]:
                if state["block_started"]:
                    events.append(f'event: content_block_stop\ndata: {json.dumps({"type":"content_block_stop","index":state["block_idx"]})}\n')
                    state["block_idx"] += 1
                state["block_started"] = False

                events.append(f'event: content_block_start\ndata: {json.dumps({"type":"content_block_start","index":idx,"content_block":{"type":"tool_use","id":tc_id,"name":tc_name,"input":{}}})}\n')
                state["block_started"] = True
                state["tool_idx"] = idx + 1
                state["current_tool"] = tc_id

            # input_json_delta
            if tc_args:
                events.append(f'event: content_block_delta\ndata: {json.dumps({"type":"content_block_delta","index":idx,"delta":{"type":"input_json_delta","partial_json":tc_args}})}\n')
        return events

    # Text delta
    content = delta.get("content")
    if content:
        if not state["block_started"]:
            events.append(f'event: content_block_start\ndata: {json.dumps({"type":"content_block_start","index":state["block_idx"],"content_block":{"type":"text","text":""}})}\n')
            state["block_started"] = True
        events.append(f'event: content_block_delta\ndata: {json.dumps({"type":"content_block_delta","index":state["block_idx"],"delta":{"type":"text_delta","text":content}})}\n')

    # finish
    if finish:
        if state["block_started"]:
            events.append(f'event: content_block_stop\ndata: {json.dumps({"type":"content_block_stop","index":state["block_idx"]})}\n')
        stop_reason = "tool_use" if finish == "tool_calls" else "end_turn" if finish == "stop" else "max_tokens" if finish == "length" else "end_turn"
        events.append(f'event: message_delta\ndata: {json.dumps({"type":"message_delta","delta":{"stop_reason":stop_reason,"stop_sequence":None},"usage":{"output_tokens":0}})}\n')
        events.append(f'event: message_stop\ndata: {json.dumps({"type":"message_stop"})}\n')

    return events


def openai_response_to_anthropic(resp: dict, model: str) -> dict:
    """Convert non-streaming OpenAI response to Anthropic format."""
    choice = (resp.get("choices", [{}]) or [{}])[0]
    msg = choice.get("message", {})
    usage = resp.get("usage", {})

    content = []
    if msg.get("content"):
        content.append({"type": "text", "text": msg["content"]})

    # Tool calls → tool_use blocks
    for tc in msg.get("tool_calls", []):
        fn = tc.get("function", {})
        try:
            inp = json.loads(fn.get("arguments", "{}"))
        except json.JSONDecodeError:
            inp = {}
        content.append({
            "type": "tool_use",
            "id": tc.get("id", ""),
            "name": fn.get("name", ""),
            "input": inp
        })

    stop_reason = "end_turn"
    finish = choice.get("finish_reason", "stop")
    if finish == "tool_calls":
        stop_reason = "tool_use"
    elif finish == "length":
        stop_reason = "max_tokens"

    return {
        "id": resp.get("id", f"msg_{uuid.uuid4().hex[:24]}"),
        "type": "message",
        "role": "assistant",
        "model": model,
        "content": content,
        "stop_reason": stop_reason,
        "stop_sequence": None,
        "usage": {
            "input_tokens": usage.get("prompt_tokens", 0),
            "output_tokens": usage.get("completion_tokens", 0)
        }
    }


# ── HTTP handler ────────────────────────────────────────────────────

class ProxyHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        sys.stderr.write(f"  [{self.log_date_time_string()}] {fmt % args}\n")
        sys.stderr.flush()

    def log_error(self, fmt, *args):
        sys.stderr.write(f"  ERR [{self.log_date_time_string()}] {fmt % args}\n")
        sys.stderr.flush()

    def _send_json(self, data, status=200):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/health":
            self._send_json({"status": "ok", "upstream": UPSTREAM, "models": MODELS})
        elif path in ("/v1/models", "/models"):
            self._send_json({
                "data": [{"id": m, "type": "model", "display_name": m} for m in MODELS],
                "has_more": False,
                "first_id": MODELS[0] if MODELS else None,
                "last_id": MODELS[-1] if MODELS else None
            })
        else:
            self._send_json({"error": "not found"}, 404)

    def do_POST(self):
        path = urlparse(self.path).path
        if path not in ("/v1/messages", "/messages"):
            self._send_json({"error": "not found"}, 404)
            return

        # Read request body
        cl = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(cl)) if cl else {}

        stream = body.get("stream", False)
        model = body.get("model", MODELS[0])
        msg_id = f"msg_{uuid.uuid4().hex[:24]}"

        # Translate & forward
        oai_body = anthropic_req_to_openai(body)
        upstream_url = f"{UPSTREAM}/chat/completions"
        req = Request(upstream_url, data=json.dumps(oai_body).encode(),
                      headers={**HEADERS, "Authorization": f"Bearer {API_KEY}"})

        try:
            if stream:
                try:
                    self.send_response(200)
                    self.send_header("Content-Type", "text/event-stream")
                    self.send_header("Cache-Control", "no-cache")
                    self.end_headers()
                    state = {"started": False, "block_started": False, "block_idx": 0, "tool_idx": 0, "current_tool": None}
                    with urlopen(req, timeout=300, context=CTX) as resp:
                        for line in resp:
                            line = line.strip()
                            if not line or line == b"data: [DONE]":
                                continue
                            if line.startswith(b"data: "):
                                try:
                                    chunk = json.loads(line[6:])
                                    for event in openai_chunk_to_anthropic_events(chunk, model, msg_id, state):
                                        self.wfile.write(event.encode())
                                        self.wfile.flush()
                                except json.JSONDecodeError:
                                    pass
                    # Final flush
                    if state["block_started"]:
                        self.wfile.write(f'event: content_block_stop\ndata: {json.dumps({"type":"content_block_stop","index":state["block_idx"]})}\n'.encode())
                        self.wfile.write(f'event: message_delta\ndata: {json.dumps({"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":None},"usage":{"output_tokens":0}})}\n'.encode())
                        self.wfile.write(f'event: message_stop\ndata: {json.dumps({"type":"message_stop"})}\n'.encode())
                    self.wfile.flush()
                except Exception as e:
                    import traceback
                    sys.stderr.write(f"  stream error: {e}\n{traceback.format_exc()}\n")
                    sys.stderr.flush()
            else:
                with urlopen(req, timeout=300, context=CTX) as resp:
                    oai_resp = json.loads(resp.read())
                self._send_json(openai_response_to_anthropic(oai_resp, model))

        except HTTPError as e:
            err = e.read()[:500]
            sys.stderr.write(f"  upstream HTTP {e.code}: {err}\n")
            sys.stderr.flush()
            self._send_json({"error": f"upstream error {e.code}: {e.reason}"}, 502)
        except URLError as e:
            sys.stderr.write(f"  upstream URLError: {e.reason}\n")
            sys.stderr.flush()
            self._send_json({"error": f"upstream unreachable: {e.reason}"}, 502)
        except Exception as e:
            import traceback
            sys.stderr.write(f"  proxy error: {e}\n{traceback.format_exc()}\n")
            sys.stderr.flush()
            self._send_json({"error": str(e)}, 500)


# ── main ────────────────────────────────────────────────────────────

def main():
    if not API_KEY:
        print("❌ OCG_PROXY_API_KEY not set. Export it first.", file=sys.stderr)
        sys.exit(1)

    server = HTTPServer(("127.0.0.1", PORT), ProxyHandler)
    print(f"ocg-proxy → {UPSTREAM}  (port {PORT})", file=sys.stderr)
    print(f"models: {', '.join(MODELS)}", file=sys.stderr)
    print(f"Claude Code: ANTHROPIC_BASE_URL=http://localhost:{PORT} ANTHROPIC_CUSTOM_MODEL_OPTION={MODELS[0]} ANTHROPIC_API_KEY=dummy claude --bare --model {MODELS[0]}", file=sys.stderr)

    def shutdown(sig, frame):
        server.shutdown()
    signal.signal(signal.SIGINT, shutdown)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    print("", file=sys.stderr)

if __name__ == "__main__":
    main()
