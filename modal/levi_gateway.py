"""FastAPI gateway in front of llama-server.

Does three jobs llama-server's own build can't do:
  1. guarantees a system message is present (server-side prompt)
  2. bearer-token auth
  3. sane defaults so a small model doesn't burn its budget on thinking
"""

import json
import os

import httpx
from fastapi import FastAPI, Request
from fastapi.responses import Response, StreamingResponse

def _load_prompt() -> str:
    env = os.environ.get("LEVI_SYSTEM_PROMPT", "").strip()
    if env:
        return env
    path = os.environ.get("LEVI_PROMPT_FILE", "/root/levi-system-prompt.txt")
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read().strip()
    except OSError:
        return ""


PROMPT = _load_prompt()
API_KEY = os.environ.get("LEVI_API_KEY", "").strip()
UPSTREAM = os.environ.get("LLAMA_UPSTREAM", "http://127.0.0.1:8081")

api = FastAPI(title="levi")


def _authorized(request: Request) -> bool:
    if not API_KEY:
        return True
    got = request.headers.get("authorization", "")
    return got.replace("Bearer ", "").strip() == API_KEY


@api.get("/health")
async def health():
    body = {"ok": True, "prompt_chars": len(PROMPT), "auth": bool(API_KEY)}
    try:
        async with httpx.AsyncClient(timeout=5) as c:
            up = await c.get(f"{UPSTREAM}/health")
        body["upstream"] = up.status_code
    except Exception as e:  # noqa: BLE001
        body["upstream"] = f"error: {e}"
    return body


@api.post("/v1/chat/completions")
async def chat(request: Request):
    if not _authorized(request):
        return Response(
            content=json.dumps({"error": {"message": "invalid api key"}}),
            status_code=401,
            media_type="application/json",
        )

    body = await request.json()
    msgs = body.get("messages") or []
    if PROMPT and not any(m.get("role") == "system" for m in msgs):
        msgs.insert(0, {"role": "system", "content": PROMPT})
    body["messages"] = msgs

    # Defaults tuned for a 30B-A3B at ~8 tok/s: don't let thinking eat the budget.
    body.setdefault("max_tokens", 1024)
    body.setdefault("temperature", 0.7)

    client = httpx.AsyncClient(timeout=None)
    req = client.build_request(
        "POST",
        f"{UPSTREAM}/v1/chat/completions",
        json=body,
        headers={"Content-Type": "application/json"},
    )
    upstream = await client.send(req, stream=True)

    async def relay():
        try:
            async for chunk in upstream.aiter_raw():
                yield chunk
        finally:
            await upstream.aclose()
            await client.aclose()

    return StreamingResponse(
        relay(),
        status_code=upstream.status_code,
        media_type=upstream.headers.get("content-type", "text/event-stream"),
    )


@api.api_route("/{path:path}", methods=["GET", "POST"])
async def passthrough(path: str, request: Request):
    if not _authorized(request):
        return Response(status_code=401)
    client = httpx.AsyncClient(timeout=None)
    body = await request.body()
    req = client.build_request(
        request.method,
        f"{UPSTREAM}/{path}",
        content=body,
        headers={"Content-Type": request.headers.get("content-type", "application/json")},
    )
    upstream = await client.send(req)
    await client.aclose()
    return Response(
        content=upstream.content,
        status_code=upstream.status_code,
        media_type=upstream.headers.get("content-type"),
    )
