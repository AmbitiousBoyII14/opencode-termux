#!/usr/bin/env python3
"""
Levi proxy — multi-provider, with automatic fallback.

Point opencode at http://127.0.0.1:8080/v1 and it Just Works.

Providers are tried in order. A provider is skipped if it has no key.
On 429 / busy / timeout, it moves to the next one automatically.

Config: keys.txt next to this file, one per line:  NAME=key
    gemini=AIza...
    nvidia=nvapi-...
    mistral=...
    zai=ccf587...
    deepseek=sk-...

Only providers with a key are enabled. At least one is required.

Measured 2026-11-12, single short request:
    z.ai free      40-137s   (queues behind paying users - unusable for agents)
    gemini free     ~2-5s
    nvidia nim      ~2-6s
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("LEVI_PROXY_PORT", "8080"))
HERE = os.path.dirname(os.path.abspath(__file__))

# name -> (openai-compatible chat url, model, extra body params)
PROVIDERS = {
    "gemini": (
        "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
        "gemini-2.5-flash",
        {},
    ),
    # Only model that answers on the free key. Measured 0.6-2.9s.
    # Other catalogue entries 404/410/503 - see NVIDIA-NOTES.md
    "nvidia": (
        "https://integrate.api.nvidia.com/v1/chat/completions",
        "nvidia/nemotron-3-ultra-550b-a55b",   # best answer quality, 1-9s
        {"chat_template_kwargs": {"enable_thinking": False}},  # 2.5x faster, no empty replies
    ),
    "mistral": (
        "https://api.mistral.ai/v1/chat/completions",
        "mistral-large-latest",
        {},
    ),
    "deepseek": (
        "https://api.deepseek.com/v1/chat/completions",
        "deepseek-chat",
        {},
    ),
    "zai": (
        "https://api.z.ai/api/paas/v4/chat/completions",
        "glm-4.7-flash",
        {"thinking": {"type": "disabled"}},   # mandatory or replies come back empty
    ),
}

# tried first-to-last; z.ai last because it's slow
ORDER = ["nvidia", "gemini", "mistral", "deepseek", "zai"]


def _load_keys():
    keys = {}
    for path in (os.path.join(HERE, "keys.txt"), os.path.expanduser("~/keys.txt")):
        try:
            with open(path, encoding="utf-8") as fh:
                for line in fh:
                    line = line.strip()
                    if not line or line.startswith("#") or "=" not in line:
                        continue
                    k, v = line.split("=", 1)
                    keys[k.strip().lower()] = v.strip()
            break
        except OSError:
            continue
    for name in PROVIDERS:
        env = os.environ.get(name.upper() + "_API_KEY")
        if env:
            keys[name] = env
    return keys


def _load_prompt():
    for p in (os.path.join(HERE, "levi-system-prompt.md"),
              os.path.expanduser("~/levi-system-prompt.md")):
        try:
            with open(p, encoding="utf-8") as fh:
                return fh.read().strip()
        except OSError:
            continue
    return ""


KEYS = _load_keys()
SYSTEM_PROMPT = _load_prompt()
ACTIVE = [n for n in ORDER if n in KEYS]


OPENER = "L \u00d7"

def _fix_opener(raw):
    """Guarantee the reply starts with the persona opener, even if the model forgot."""
    try:
        d = json.loads(raw)
        ch = d.get("choices") or []
        if not ch:
            return raw
        msg = ch[0].get("message") or {}
        c = msg.get("content")
        if not isinstance(c, str) or not c.strip():
            return raw
        head = c.lstrip()[:12]
        if OPENER in head or "L \u00d7" in head:
            return raw
        msg["content"] = OPENER + "\n\n" + c.lstrip()
        return json.dumps(d).encode()
    except Exception:
        return raw


def _is_empty_reply(raw):
    """True when the model returned no visible text (reasoning ate the budget)."""
    try:
        d = json.loads(raw)
        msg = (d.get("choices") or [{}])[0].get("message") or {}
        return not (msg.get("content") or "").strip()
    except Exception:
        return False


def log(*a):
    print(*a, file=sys.stderr, flush=True)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _send(self, code, payload):
        raw = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def _stream(self, resp, provider, model=""):
        self.send_response(resp.status)
        self.send_header("Content-Type", resp.headers.get("Content-Type", "text/event-stream"))
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()

        sent_opener = False
        pending = ""
        buf = b""

        def emit(ev):
            self.wfile.write(b"%x\r\n%s\r\n" % (len(ev), ev))
            self.wfile.flush()

        while True:
            chunk = resp.read(2048)
            if not chunk:
                break
            buf += chunk
            # process complete SSE events only
            while b"\n\n" in buf:
                ev, buf = buf.split(b"\n\n", 1)
                ev += b"\n\n"
                if sent_opener:
                    emit(ev)
                    continue
                data = None
                for line in ev.split(b"\n"):
                    if line.startswith(b"data: "):
                        data = line[6:].strip()
                if not data or data == b"[DONE]":
                    emit(ev)            # keep keep-alives / terminators flowing
                    continue
                try:
                    d = json.loads(data)
                    ch = d.get("choices") or []
                    if not ch:
                        emit(ev)
                        continue
                    delta = ch[0].get("delta") or {}
                    c = delta.get("content")
                    if c and not sent_opener:
                        pending += c          # buffer until we can judge the opener
                        if len(pending.lstrip()) < 12:
                            continue          # not enough yet, decide later
                        body_txt = pending.lstrip()
                        if not body_txt.startswith(OPENER):
                            pending = OPENER + "\n\n" + body_txt
                        delta["content"] = pending
                        pending = ""
                        sent_opener = True
                        emit(b"data: " + json.dumps(d).encode() + b"\n\n")
                        continue
                    if delta.get("reasoning_content") and not c and not sent_opener:
                        continue              # swallow reasoning preamble
                    emit(ev)
                except Exception:
                    emit(ev)
        if pending:
            emit(b"data: " + json.dumps({"choices":[{"delta":{"content":pending},
                  "index":0,"finish_reason":None}]}).encode() + b"\n\n")
        if buf:
            emit(buf)
        self.wfile.write(b"0\r\n\r\n")
        self.wfile.flush()

    def do_GET(self):
        path = self.path.rstrip("/")
        if path in ("/health", "/v1/health"):
            return self._send(200, {
                "ok": bool(ACTIVE), "providers": ACTIVE,
                "prompt_chars": len(SYSTEM_PROMPT),
            })
        if path.endswith("/models"):
            return self._send(200, {"object": "list", "data": [
                {"id": "glm-4.7-flash", "object": "model", "owned_by": "levi"}]})
        self._send(404, {"error": {"message": "not found"}})

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        try:
            body = json.loads(self.rfile.read(n) or b"{}")
        except Exception:
            return self._send(400, {"error": {"message": "bad json"}})

        msgs = body.get("messages") or []
        if SYSTEM_PROMPT:
            msgs = [m for m in msgs if m.get("role") != "system"]
            msgs.insert(0, {"role": "system", "content": SYSTEM_PROMPT})
        body["messages"] = msgs
        body.pop("model", None)          # provider decides
        if body.get("max_tokens") is None:
            body.setdefault("max_tokens", 4096)
        stream = bool(body.get("stream"))
        # keep client happy: it asked for a model name it knows
        body_out_source = body

        last_err = None
        for provider in ACTIVE:
            url, model, extra = PROVIDERS[provider]
            payload = dict(body_out_source)
            payload["model"] = model
            payload.update(extra)

            for attempt in range(3):
                req = urllib.request.Request(
                    url, data=json.dumps(payload).encode(),
                    headers={"Content-Type": "application/json",
                             "Authorization": "Bearer " + KEYS[provider],
                             "Accept": "text/event-stream" if stream else "application/json"},
                )
                t0 = time.time()
                try:
                    resp = urllib.request.urlopen(req, timeout=240)
                except urllib.error.HTTPError as e:
                    raw = e.read()
                    try:
                        err = json.loads(raw)
                    except Exception:
                        err = {"error": {"message": raw[:150].decode("utf-8", "replace")}}
                    code = str(err.get("error", {}).get("code", ""))
                    msg = str(err.get("error", {}).get("message", ""))[:70]
                    last_err = f"{provider}: {code} {msg}"
                    log(f"  {provider} attempt {attempt + 1} fail: {last_err}")
                    if e.code == 429 or code in ("1305", "1113"):
                        time.sleep(2 + 2 * attempt)
                        continue
                    break                      # hard failure -> next provider
                except Exception as e:          # noqa: BLE001
                    last_err = f"{provider}: {type(e).__name__}"
                    log(f"  {provider} attempt {attempt + 1} {last_err}")
                    time.sleep(2 + 2 * attempt)
                    continue

                dt = time.time() - t0
                if stream:
                    log(f"  served by {provider} ({model}) in {dt:.1f}s")
                    return self._stream(resp, provider, model)

                raw = resp.read()
                if _is_empty_reply(raw) and attempt < 2:
                    old_mt = payload.get("max_tokens") or 0
                    payload["max_tokens"] = min(32768, max(4096, old_mt * 4))
                    log(f"  {provider} empty content (budget eaten by reasoning) "
                        f"-> retry max_tokens {old_mt}->{payload['max_tokens']}")
                    continue

                log(f"  served by {provider} ({model}) in {dt:.1f}s")
                return self._send(200, _fix_opener(raw))

        self._send(503, {"error": {
            "message": f"all providers failed. last: {last_err}",
            "code": 1305}})


if __name__ == "__main__":
    if not ACTIVE:
        log("No API keys. Create keys.txt next to this file:")
        log("  gemini=YOUR_KEY      # https://aistudio.google.com/apikey  (fast, free)")
        log("  nvidia=nvapi-...     # https://build.nvidia.com             (free)")
        log("  zai=YOUR_KEY         # slow on free tier")
        sys.exit(1)
    log(f"providers (in order): {', '.join(ACTIVE)}")
    log(f"prompt: {len(SYSTEM_PROMPT)} chars")
    log(f"listening: http://127.0.0.1:{PORT}/v1")
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
