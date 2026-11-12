#!/usr/bin/env python3
"""
Z.ai -> OpenAI-compatible proxy. Pure stdlib, runs on Termux.

Why it exists:
  1. GLM-4.7 THINKS COMPULSORILY. Without thinking disabled, a 120-token budget
     gets spent entirely on reasoning_tokens and the visible reply is EMPTY.
  2. Z.ai returns 429 / code 1305 ("temporarily overloaded") fairly often.
     This retries with backoff instead of surfacing the error.
  3. Injects the system prompt so the client can't drop it.

Run:   python3 zai-proxy.py
Then:  point opencode at http://127.0.0.1:8080/v1  (apiKey can be anything)
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

UPSTREAM = "https://api.z.ai/api/paas/v4/chat/completions"
MODEL = "glm-4.7-flash"
PORT = int(os.environ.get("ZAI_PROXY_PORT", "8080"))
MAX_RETRIES = 12

HERE = os.path.dirname(os.path.abspath(__file__))


def _read_first(*paths):
    for p in paths:
        try:
            with open(p, encoding="utf-8") as fh:
                return fh.read().strip()
        except OSError:
            continue
    return ""


API_KEY = os.environ.get("ZAI_API_KEY") or _read_first(
    os.path.join(HERE, "zai-key.txt"),
    os.path.expanduser("~/zai-key.txt"),
    os.path.expanduser("~/.zai-key"),
)
SYSTEM_PROMPT = _read_first(
    os.path.join(HERE, "levi-system-prompt.md"),
    os.path.expanduser("~/levi-system-prompt.md"),
)


def log(*a):
    print(*a, file=sys.stderr, flush=True)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):  # silence default access log
        pass

    # ---------------------------------------------------------------- helpers
    def _send(self, code, payload, ctype="application/json"):
        raw = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def _stream(self, resp):
        self.send_response(resp.status)
        self.send_header("Content-Type", resp.headers.get("Content-Type", "text/event-stream"))
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()
        while True:
            chunk = resp.read(1024)
            if not chunk:
                break
            self.wfile.write(b"%x\r\n%s\r\n" % (len(chunk), chunk))
            self.wfile.flush()
        self.wfile.write(b"0\r\n\r\n")
        self.wfile.flush()

    # ------------------------------------------------------------------ routes
    def do_GET(self):
        if self.path.rstrip("/") in ("/health", "/v1/health"):
            return self._send(200, {
                "ok": bool(API_KEY),
                "model": MODEL,
                "prompt_chars": len(SYSTEM_PROMPT),
                "upstream": UPSTREAM,
            })
        if self.path.rstrip("/").endswith("/models"):
            return self._send(200, {"object": "list", "data": [
                {"id": MODEL, "object": "model", "owned_by": "z.ai"}]})
        self._send(404, {"error": {"message": "not found"}})

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        try:
            body = json.loads(self.rfile.read(n) or b"{}")
        except Exception:
            return self._send(400, {"error": {"message": "bad json"}})

        msgs = body.get("messages") or []
        # ALWAYS own the system message. opencode sends its own harness prompt
        # ("You are opencode, an AI coding agent...") which buries Levi's persona.
        # Observed: model introduced itself as "an AI assistant running in
        # OpenCode" instead of using the L x opener. Replace, don't append.
        if SYSTEM_PROMPT:
            msgs = [m for m in msgs if m.get("role") != "system"]
            msgs.insert(0, {"role": "system", "content": SYSTEM_PROMPT})
        body["messages"] = msgs
        body.setdefault("model", MODEL)
        # The single most important line in this file:
        body.setdefault("thinking", {"type": "disabled"})
        if body.get("max_tokens") is None:
            body.setdefault("max_tokens", 2048)

        stream = bool(body.get("stream"))
        data = json.dumps(body).encode()
        headers = {
            "Content-Type": "application/json",
            "Authorization": "Bearer " + API_KEY,
            "Accept": "text/event-stream" if stream else "application/json",
        }

        for attempt in range(MAX_RETRIES):
            req = urllib.request.Request(UPSTREAM, data=data, headers=headers)
            try:
                resp = urllib.request.urlopen(req, timeout=300)
            except urllib.error.HTTPError as e:
                raw = e.read()
                try:
                    err = json.loads(raw)
                except Exception:
                    err = {"error": {"message": raw[:200].decode("utf-8", "replace")}}
                code = str(err.get("error", {}).get("code", ""))
                # 1305 = "service may be temporarily overloaded"
                if code == "1305" or e.code == 429:
                    wait = min(3 + 3 * attempt, 30)
                    log(f"  busy (attempt {attempt + 1}/{MAX_RETRIES}), waiting {wait}s")
                    time.sleep(wait)
                    continue
                return self._send(e.code, err)
            except Exception as e:  # noqa: BLE001
                log(f"  network error: {e}")
                time.sleep(3 + attempt)
                continue

            if stream:
                return self._stream(resp)
            return self._send(200, resp.read())

        self._send(503, {"error": {"message": "z.ai free tier busy - try again in a moment (code 1305)", "code": 1305}})


if __name__ == "__main__":
    if not API_KEY:
        log("No API key. Put it in zai-key.txt next to this file, or set ZAI_API_KEY.")
        sys.exit(1)
    log(f"prompt: {len(SYSTEM_PROMPT)} chars   model: {MODEL}")
    log(f"listening: http://127.0.0.1:{PORT}/v1")
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
