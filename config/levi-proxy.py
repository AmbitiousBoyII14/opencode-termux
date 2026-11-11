#!/usr/bin/env python3
"""
levi-proxy — strips the server-injected persona header from an OpenAI-compatible
endpoint and replaces it with your own.

Why this exists
---------------
The "LEVI -> 🔎" header is added AFTER the model finishes, by middleware on the
server. Proof: asking the model to reply "BANANA" returns "LEVI -> 🍌" — the word
was swapped for an emoji, which no prompt can do. System messages, user messages,
and AGENTS.md all fail to remove it because the model never writes it.

So the fix has to sit between the server's output and your client. That is this
proxy. It is stateless and forwards everything it does not understand.

Usage
-----
    python3 levi-proxy.py --upstream https://host/v1 --port 8787

Then point opencode at the proxy instead of the endpoint:

    "baseURL": "http://127.0.0.1:8787/v1"

Options
    --header "Levi 👾 -> Activated 👾!"   replacement first line
    --strip-canned                        also drop the "Awaiting target
                                          specification." boilerplate block
    --no-replace                          drop the header, inject nothing
"""

from __future__ import annotations

import argparse
import http.server
import json
import re
import socketserver
import sys
import urllib.error
import urllib.request

DEFAULT_HEADER = "Levi 👾 -> Activated 👾!"

# A line the server prepends, e.g. "LEVI -> 🔎" or "LEVI -> Levi Assistant Active 🧬"
HEADER_RE = re.compile(r"^\s*LEVI\s*[-=]>.*$", re.IGNORECASE)

# The canned interrogation block the server returns for vague input.
CANNED_START_RE = re.compile(r"^\s*Awaiting target specification\.?\s*$", re.IGNORECASE)

CONFIG = argparse.Namespace(
    upstream="",
    header=DEFAULT_HEADER,
    replace=True,
    strip_canned=False,
)


def strip_header(text: str) -> tuple[str, bool]:
    """Remove a leading LEVI header line. Returns (text, had_header)."""
    had = False
    lines = text.split("\n")
    while lines and HEADER_RE.match(lines[0]):
        lines.pop(0)
        had = True
    # A header may be followed by one blank line; keep the body tight.
    while lines and lines[0].strip() == "":
        lines.pop(0)
    return "\n".join(lines), had


def strip_canned(text: str) -> str:
    """Drop the 'Awaiting target specification.' block and its numbered list."""
    lines = text.split("\n")
    for i, line in enumerate(lines):
        if CANNED_START_RE.match(line):
            return "\n".join(lines[:i]).rstrip()
    return text


def rewrite(text: str, session_start: bool) -> str:
    if not text:
        return text
    body, had = strip_header(text)
    if CONFIG.strip_canned:
        body = strip_canned(body)
    if not CONFIG.replace:
        return body
    # Show the replacement intro only on the first turn of a session, so it
    # reads as an activation banner rather than a per-message tag.
    if had or session_start:
        return CONFIG.header + ("\n\n" + body if body.strip() else "")
    return body


def is_session_start(payload: dict) -> bool:
    """Heuristic: one user message and no assistant turn yet."""
    msgs = payload.get("messages") or []
    roles = [m.get("role") for m in msgs if isinstance(m, dict)]
    return roles.count("user") <= 1 and "assistant" not in roles


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # quieter logs
        if "error" in (fmt % args).lower():
            sys.stderr.write("  " + (fmt % args) + "\n")

    # ── helpers ──────────────────────────────────────────────────────────────
    def _upstream_url(self) -> str:
        path = self.path
        if path.startswith("/v1"):
            return CONFIG.upstream.rstrip("/") + path[3:]
        return CONFIG.upstream.rstrip("/") + path

    def _forward(self, body: bytes | None):
        req = urllib.request.Request(
            self._upstream_url(),
            data=body,
            method=self.command,
        )
        for k, v in self.headers.items():
            if k.lower() in ("host", "content-length", "accept-encoding", "connection"):
                continue
            req.add_header(k, v)
        req.add_header("Accept-Encoding", "identity")
        return urllib.request.urlopen(req, timeout=300)

    def _send_plain(self, code: int, body: bytes, ctype="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    # ── routes ───────────────────────────────────────────────────────────────
    def do_GET(self):
        try:
            with self._forward(None) as r:
                self._send_plain(r.status, r.read(), r.headers.get("Content-Type", "application/json"))
        except urllib.error.HTTPError as e:
            self._send_plain(e.code, e.read(), e.headers.get("Content-Type", "application/json"))
        except Exception as e:
            self._send_plain(502, json.dumps({"error": str(e)}).encode())

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b""
        try:
            payload = json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            payload = {}

        is_chat = "/chat/completions" in self.path
        stream = bool(payload.get("stream"))

        if not is_chat:
            try:
                with self._forward(raw) as r:
                    self._send_plain(r.status, r.read(), r.headers.get("Content-Type", "application/json"))
            except urllib.error.HTTPError as e:
                self._send_plain(e.code, e.read(), e.headers.get("Content-Type", "application/json"))
            except Exception as e:
                self._send_plain(502, json.dumps({"error": str(e)}).encode())
            return

        session_start = is_session_start(payload)

        try:
            with self._forward(raw) as r:
                if stream:
                    self._stream(r, session_start)
                else:
                    data = json.loads(r.read() or b"{}")
                    self._rewrite_json(data, session_start)
                    body = json.dumps(data).encode()
                    self._send_plain(200, body)
        except urllib.error.HTTPError as e:
            self._send_plain(e.code, e.read(), e.headers.get("Content-Type", "application/json"))
        except Exception as e:
            self._send_plain(502, json.dumps({"error": str(e)}).encode())

    # ── response rewriting ───────────────────────────────────────────────────
    def _rewrite_json(self, data: dict, session_start: bool):
        for choice in data.get("choices") or []:
            msg = choice.get("message") or {}
            if isinstance(msg.get("content"), str):
                msg["content"] = rewrite(msg["content"], session_start)

    def _stream(self, upstream, session_start: bool):
        """Pass SSE through, holding the leading content until the header is decided.

        A role-only chunk does NOT mean the text has started: servers send
        {"delta":{"role":"assistant"}} first. Deciding on that leaked the
        original header straight through, so only content text and tool_calls
        settle the decision.
        """
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()

        decided = False
        text = ""            # accumulated leading content, not yet emitted
        held: list[dict] = []  # chunks withheld until we decide

        def emit(obj):
            self.wfile.write(b"data: " + json.dumps(obj).encode() + b"\n\n")
            self.wfile.flush()

        def flush_held(replacement: str | None):
            """Emit the held chunks, folding `replacement` into the first content."""
            nonlocal held
            if not held:
                if replacement:
                    synth = {"choices": [{"index": 0, "delta": {"content": replacement}}]}
                    emit(synth)
                return
            first = json.loads(json.dumps(held[0]))
            try:
                first["choices"][0].setdefault("delta", {})
                if replacement:
                    first["choices"][0]["delta"]["content"] = replacement
                else:
                    first["choices"][0]["delta"].pop("content", None)
            except (KeyError, IndexError):
                pass
            emit(first)
            # The held chunks after the first still carry their original text.
            # `replacement` already contains all of it, so drop theirs or the
            # reply comes out doubled.
            for h in held[1:]:
                try:
                    h["choices"][0].get("delta", {}).pop("content", None)
                except (KeyError, IndexError):
                    pass
                emit(h)
            held = []

        for raw_line in upstream:
            line = raw_line.decode("utf-8", "replace").rstrip("\n")
            if not line.startswith("data:"):
                continue
            chunk = line[5:].strip()
            if chunk == "[DONE]":
                if not decided:
                    body, _ = strip_header(text)
                    if CONFIG.strip_canned:
                        body = strip_canned(body)
                    rep = None
                    if CONFIG.replace and session_start:
                        rep = CONFIG.header + ("\n\n" + body if body.strip() else "")
                    elif CONFIG.replace:
                        rep = ""
                    flush_held(rep)
                    decided = True
                self.wfile.write(b"data: [DONE]\n\n")
                self.wfile.flush()
                break
            try:
                obj = json.loads(chunk)
            except json.JSONDecodeError:
                continue

            if decided:
                emit(obj)
                continue

            choice = (obj.get("choices") or [{}])[0]
            delta = choice.get("delta") or {}
            piece = delta.get("content")

            # Tool call or finish arrives before any text: release and go straight.
            if delta.get("tool_calls") or choice.get("finish_reason"):
                rep = CONFIG.header + "\n\n" if (CONFIG.replace and session_start) else None
                flush_held(rep)
                decided = True
                emit(obj)
                continue

            if isinstance(piece, str):
                text += piece
                held.append(obj)

                # Decide only when the first line can no longer become a header.
                # "LEVI -> Levi Assistant Active" streams in fragments, so a
                # partial "LEV" must be held, while plain prose can go at once.
                head = text.upper().lstrip()
                if "\n" in text:
                    ready = True                      # first line is complete
                elif "LEVI".startswith(head[:4]) and len(head) < 4:
                    ready = False                     # still could be "LEVI"
                elif head.startswith("LEVI"):
                    ready = False                     # header in progress
                elif len(head) >= 4:
                    ready = True                      # definitely prose
                elif len(text) > 2000:
                    ready = True                      # safety valve
                else:
                    ready = False

                if ready:
                    body, had = strip_header(text)
                    if CONFIG.strip_canned:
                        body = strip_canned(body)
                    if CONFIG.replace and (had or session_start):
                        rep = CONFIG.header + ("\n\n" + body if body.strip() else "")
                    else:
                        rep = body
                    flush_held(rep)
                    decided = True
                continue

            # role-only or empty delta: hold it, it carries no text
            held.append(obj)

class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--upstream", required=True, help="e.g. https://host/v1")
    ap.add_argument("--port", type=int, default=8787)
    ap.add_argument("--header", default=DEFAULT_HEADER)
    ap.add_argument("--strip-canned", action="store_true")
    ap.add_argument("--no-replace", action="store_true")
    a = ap.parse_args()

    CONFIG.upstream = a.upstream
    CONFIG.header = a.header
    CONFIG.replace = not a.no_replace
    CONFIG.strip_canned = a.strip_canned

    print(f"levi-proxy  {a.upstream}  ->  http://127.0.0.1:{a.port}/v1")
    print(f"header      {a.header!r}")
    print(f"strip canned: {a.strip_canned}   replace: {CONFIG.replace}")
    Server(("0.0.0.0", a.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
