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
