# NVIDIA NIM — what actually works on a free key

Tested 2026-11-12 with a real `nvapi-` key. The catalogue advertises 83 models.
On this account **exactly one answered**.

## Working

```
nvidia/nemotron-3-nano-omni-30b-a3b-reasoning
```

30B total / 3B active MoE — same class as GLM-4.7-Flash. Different family, but it
follows the prompt correctly.

Measured through the proxy:

| query | time | reply |
|---|---|---|
| say ready | 0.67s | `L × ready` |
| hello | 1.05s | `L ×  Hi, how can I assist you with your Android game modding` |
| what is a JNI hook | 2.26s | `L ×  A JNI hook is a mechanism that lets you intercept…` |
| hello world in python | 3.72s | `L ×` + correct code block |
| count to 3 | 1.69s | `L × 1\n2\n3` |
| streaming | 0.88s | clean SSE chunks |

**vs z.ai free:** 40–140s per call. This is ~60x faster.

## Not working on a free key

| model | error |
|---|---|
| `z-ai/glm-5.3-flash` | hangs past 75s |
| `deepseek-ai/deepseek-v4.1-flash` | hangs past 75s |
| `nvidia/nemotron-3-super-120b-a12b` | 404 — function not found |
| `google/gemma-4-31b-it` | 404 |
| `moonshotai/kimi-k2.6` | 404 |
| `deepseek-ai/deepseek-coder-6.7b-instruct` | 404 |
| `minimaxai/minimax-m3.1-flash` | 503 content safety screening unavailable |
| `openai/gpt-oss-20b` | times out |
| `meta/llama-4-maverick-17b-128e-instruct` | 410 gone |
| `qwen/qwen3.5-397b-a17b` | 410 gone |

The 404s suggest the catalogue is a global list while the free key is scoped to
a subset. 410s are genuinely retired models. The hangs are the interesting
failure — a model that accepts the request then never generates.

## Free tier facts

- no credit card
- **phone verification required** (SMS)
- ~40 RPM, model-specific, not guaranteed
- **no documented daily token cap** — the differentiator vs Gemini
- key valid 6 months, renew in dashboard
- rate limits are per-model; a 429 is normal on popular models

## The model's quirk

Nemotron Nano is a **reasoning** model — it emits `reasoning_content` alongside
`content`, always, and there is no documented switch to turn it off (unlike
z.ai's `thinking: {"type":"disabled"}`).

Measured reasoning overhead is small — 23–42 tokens on short queries — so it
costs a second or two, not the empty-reply disaster that z.ai has. The proxy
passes it through; opencode reads `content` and ignores the rest.

## Config used

```python
"nvidia": (
    "https://integrate.api.nvidia.com/v1/chat/completions",
    "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning",
    {},
),
```

`ORDER = ["nvidia", "gemini", "mistral", "deepseek", "zai"]` — nvidia first,
z.ai last because it's slow.
