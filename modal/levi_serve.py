"""FastAPI gateway. Sits in front of vLLM (127.0.0.1:8001) on port 8000.

Its only job: guarantee a system message exists, then stream the response
straight back. vLLM never sees a request without the prompt.
"""

import os

import httpx
from fastapi import FastAPI, Request
from fastapi.responses import Response, StreamingResponse

PROMPT = os.environ.get("LEVI_SYSTEM_PROMPT", "").strip()
UPSTREAM = "http://127.0.0.1:8001"
api = FastAPI(title="levi")


@api.get("/health")
async def health():
    return {"ok": True, "prompt_chars": len(PROMPT), "upstream": UPSTREAM}


@api.post("/v1/chat/completions")
async def chat(request: Request):
    body = await request.json()
    msgs = body.get("messages") or []
    if PROMPT and not any(m.get("role") == "system" for m in msgs):
        msgs.insert(0, {"role": "system", "content": PROMPT})
    body["messages"] = msgs

    client = httpx.AsyncClient(timeout=None)
    req = client.build_request(
        "POST", f"{UPSTREAM}/v1/chat/completions", json=body,
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
    client = httpx.AsyncClient(timeout=None)
    body = await request.body()
    req = client.build_request(
        request.method, f"{UPSTREAM}/{path}", content=body,
        headers={"Content-Type": request.headers.get("content-type", "application/json")},
    )
    upstream = await client.send(req)
    await client.aclose()
    return Response(
        content=upstream.content,
        status_code=upstream.status_code,
        media_type=upstream.headers.get("content-type"),
    )
