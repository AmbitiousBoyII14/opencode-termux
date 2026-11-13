# NVIDIA free key — full catalogue sweep

**You were right, I was wrong.** My first pass tested 10 models and concluded
"only Nemotron Nano works". A complete sweep of all **83** models found **15**
that respond. Tested 2026-11-12, free `nvapi-` key.

## Working chat models

| model | first-token latency | content | verdict |
|---|---|---|---|
| **nvidia/nemotron-3-ultra-550b-a55b** | **0.6–1.8s** | always full | **← default now** |
| nvidia/nemotron-3-nano-omni-30b-a3b-reasoning | 0.8–2.9s | full | previous default |
| nvidia/nemotron-3.5-super-vl-120b-a12b | 1.0s | full | vision-capable |
| nvidia/nemotron-3.5-lightning-30b-a3b | 3.3s | full | fastest *variant* name, not fastest |
| minimaxai/minimax-m3.1-flash | 0.8s | **sometimes empty** | 0 reasoning, unreliable |
| mistralai/mistral-large-4-1t-a52b | 24.9s | full | too slow |
| nvidia/nemotron-3.5-bolt-e4b | 0.3s | full | small |
| poolside/laguna-xs-2.1 | 0.2s | full | small, coding-focused |
| nvidia/ising-calibration-1.5-31b | 29.3s | full | too slow |
| nvidia/riva-translate-4b-instruct-v2 | 0.3s | echoes input | translation only |
| stepfun-ai/step-5-preview | 1.2s | empty on probe | untested |
| openai/gpt-oss-20b | 88.5s | empty | effectively broken |

Special-purpose (not chat): `meta/llama-guard-4-12b`,
`nvidia/llama-3.1-nemotron-safety-guard-8b-v3`, `nvidia/nemotron-parse-2.0`,
`nvidia/nemotron-3-embed-*`, `nvidia/nvclip`.

## Failures

```
404  60 models   "Function '<uuid>': Not found for account"
500   2 models   internal error
400   1 model    nemotron-parse (needs image input, not text)
timeout 3 models deepseek-v4.1-flash, llama-3.2-90b-vision, nemoguard-content-safety
```

**The 404s are the answer to "is only one model free".** The message is
`Not found for account` — the catalogue is global, but a free key is provisioned
a subset. 60 of 83 aren't assigned to this account at all.

**DeepSeek on NVIDIA: not available.** Both `deepseek-v4.1-flash` and
`deepseek-coder-6.7b-instruct` are 404 on this key. DeepSeek Flash works only
through DeepSeek's own API (paid, $0.15/$0.60 per M off-peak).

## Quality comparison

Same question, hard modding problem:

> My ImGui menu crashes the game on ARM64 when I open it. KittyMemory patch
> applied fine. Give the 3 most likely causes, one line each on how to verify.

**nemotron-3-ultra-550b** (8.6s) — specific and actionable:
1. ImGui context/frame not initialized — check `ImGui::GetCurrentContext()` and `NewFrame()` ordering
2. Stack alignment violation in ARM64 trampoline — verify `((uintptr_t)sp & 0xF) == 0`
3. EGL/OpenGL context mismatch — log `eglGetCurrentContext()` in the render hook

**nemotron-3-nano-30b** (2.4s) — generic:
1. Invalid memory access in render loop — check logcat for SIGSEGV
2. ABI mismatch — `readelf -h libImGui.so` vs `getprop ro.product.cpu.abi`
3. Threading — ImGui called off main thread

Both correct. The 550B names the actual APIs and the alignment check; the 30B
gives generic triage. For real work, use the 550B.

**minimax-m3.1-flash** returned an empty string on this test — same failure mode
as z.ai with thinking enabled. Skip it.

## Recommendation

```python
"nvidia": (
    "https://integrate.api.nvidia.com/v1/chat/completions",
    "nvidia/nemotron-3-ultra-550b-a55b",
    {},
),
```

Free, no card, 0.6–1.8s on short prompts, 8.6s on a real 700-token answer, and
it produces the best technical answers of anything tested in this whole project.

---

## THE BIG ONE: empty replies at large context (fixed 2026-11-13)

This is the bug that looked like "Nemotron crashed". It is not a crash — it is
the reasoning model silently eating the entire output budget.

### Reproduction (deterministic, 100%)

At **~80K tokens of context**, on BOTH nvidia models:

| max_tokens | content | reasoning | finish_reason |
|---|---|---|---|
| 64 | **0 chars** | 253 | `length` |
| 128 | **0 chars** | 522 | `length` |
| 300 | **0 chars** | 1174 | `length` |
| 1024 | 1861 | 1125 | `stop` |
| 8192 | 3292 | 1686 | `stop` |

The model spends every single token on `reasoning_content`, hits `max_tokens`,
and returns `content: ""`. opencode renders that as a build that did nothing
or as utter garbage. **The failure is proportional to context size: at 5K
tokens you never see it, at 80K you see it every time.**

### Two independent fixes, both now in the proxy

**1. Disable thinking** — `chat_template_kwargs.enable_thinking: false`

| flag | content | reasoning | time @80K |
|---|---|---|---|
| none | 0 | 1174 | 37.7s |
| `chat_template_kwargs.enable_thinking: false` | 1752 | **0** | **17.7s** |
| `thinking: {type: disabled}` | 2624 | 0 | 21.7s |
| `reasoning_effort: none` | 2380 | 0 | 16.4s |
| `reasoning_budget: 0` | 2865 | 0 | 30.7s |
| `reasoning_effort: low` | 2526 | 1048 | 31.5s ← does NOT disable |

All of these are accepted (no 400). `enable_thinking: false` is fastest.

**2. Auto-retry with a bigger budget** — if `content` comes back empty, the
proxy now retries with `max_tokens × 4` (capped 32768). Tested: 80K context
with a 256-token client budget returns 951 chars in 10.7s instead of nothing.

### Why the persona broke at long context too

At 80K the model stopped emitting `L ×`. Fixed proxy-side: the opener is now
injected into non-stream responses, and the SSE path buffers the first content
delta until it can judge, then injects `L ×` if missing. Verified streaming
at 80K: `L ×` once, no duplicate.

### Verified after the fix

| test | context | time | result |
|---|---|---|---|
| non-stream | 5K | 14.3s | `L ×` + real answer |
| non-stream | 20K | 19.7s | `L ×` + real answer |
| non-stream | 80K | 41.8s | `L ×` + real answer |
| non-stream, 256-token budget | 80K | 8.3s | `L ×` + real answer |
| **SSE stream** | 80K | **13.3s, first token 2.3s** | `L ×` once, clean |

### Practical advice

Keep opencode sessions under ~40K tokens and this never happens. The proxy now
handles it if you don't, but long context is still slower and costs more of
the model's attention.
