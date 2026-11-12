# Z.ai — free GLM-4.7-Flash, 128K context, no card

**This replaces the Modal deployment entirely.** Same model, unquantized, 128K
context, $0. Verified live 2026-11-12.

## The one thing that breaks everything

**GLM-4.7 thinks compulsorily.** If you don't disable thinking, your entire
`max_tokens` budget is consumed by `reasoning_tokens` and `message.content`
comes back **empty string**. Observed:

```
max_tokens: 120, thinking on   -> content: ""            reasoning_tokens: 120
max_tokens: 600, thinking on   -> content: "L × Ready…"  reasoning_tokens: 280
thinking: {"type":"disabled"}  -> content: "L × Ready."  reasoning_tokens: 0    [17s]
```

Every request needs:

```json
"thinking": {"type": "disabled"}
```

The proxy does this for you. Don't call `api.z.ai` directly from a client that
won't send it.

## Why the proxy exists

`zai-proxy.py` is **pure stdlib** — `http.server` + `urllib`. No pip, no
dependencies, works on bare Termux. It does three things:

1. forces `thinking: {"type":"disabled"}`
2. injects `levi-system-prompt.md` as the system message if absent
3. retries code `1305` / HTTP 429 with backoff

## Verified results

| test | result |
|---|---|
| `say ready` | `L ×\n\nReady.` — 6 tokens, 0 reasoning, 17 s |
| `hello` | `L ×\n\nHello. I'm ready. What project…` |
| `what is a JNI hook` | `L ×\n\n**JNI Hook** refers to…` — no `LEVI ->`, no canned block |
| **5770-token system prompt** | ✅ **`L ×\n\nReady.`** — this is the case that killed Modal |
| streaming (SSE) | ✅ clean `chat.completion.chunk` deltas |

## Setup on Termux

```bash
mkdir -p ~/zai && cd ~/zai
curl -fsSL -o zai-proxy.py  <url-to-this-repo>/zai/zai-proxy.py
curl -fsSL -o levi-system-prompt.md <url>/zai/levi-system-prompt.md
echo 'YOUR_KEY' > zai-key.txt && chmod 600 zai-key.txt

python3 zai-proxy.py          # listens on 127.0.0.1:8080
```

No `pkg install`, no venv. If `python3` exists, this runs.

Keep it alive in the background:
```bash
nohup python3 zai-proxy.py > zai.log 2>&1 &
```

## opencode config

```jsonc
{
  "provider": {
    "levi": {
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "http://127.0.0.1:8080/v1",
        "apiKey": "unused"
      },
      "models": { "glm-4.7-flash": { "name": "Levi" } }
    }
  },
  "model": "levi/glm-4.7-flash"
}
```

## Honest performance notes

The free tier is **busy**. Measured across ~10 calls:

- **429 / code 1305** on roughly half of first attempts
- one call took **8 attempts and 84 s** to get through
- successful calls: **17 s** (short), **49 s** (hello), **101 s** (300-token answer)

The proxy's retries make this tolerable, not invisible. First message of a
session may take a minute. Subsequent ones are quicker because the system
prompt is cached (`cached_tokens: 362`).

If it's too slow, DeepSeek V4.1-Flash is **$0.15/$0.60 per M off-peak** with
**$0.003/M cache hits** — for your workload (same 6.3K prefix every turn) that's
pennies a month, and it's fast.

## Free tier facts

From Z.ai's live pricing page:
```
GLM-4.7-Flash      Free  Free  Free  Free
GLM-4.5-Flash      Free  Free  Free  Free
```
Input, cached input, cache storage, output — all free. Context is **128K**
(`max: 131072`), not the 8K that broke Modal.

Note the name is `glm-4.7-flash` (hyphens). `GLM-4.7-Flash` is accepted in the
web UI but use hyphens in API calls.

## Files
- `zai-proxy.py` — the proxy, stdlib only
- `levi-system-prompt.md` — server-side prompt, 1875 chars
- `zai-key.txt` — your key (chmod 600, do not commit)
