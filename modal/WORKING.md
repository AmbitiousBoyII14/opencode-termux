# Levi on Modal — WORKING

**Status: live on free CPU, no payment method.** Verified 2026-11-11.

```
URL   https://syamthandasawoni--levi-serve.us-east.modal.run/v1
KEY   /home/user/levi-modal-key.txt   (not in git, not in this file)
```

`GET /health` → `{"ok":true,"prompt_chars":1875,"auth":true,"upstream":200}`

`prompt_chars` 1875 = the exact byte count of `levi-system-prompt.md`. If that
number changes without you editing the file, you're hitting a stale container.

## Acceptance — 4/4 clean

| query | first chars | L × | no `LEVI ->` | no canned block |
|---|---|---|---|---|
| say ready | `L ×\n\nReady.` | ✅ | ✅ | ✅ |
| hello | `L ×\n\nWhat are you working on?` | ✅ | ✅ | ✅ |
| hello world | `L ×\n\nTo run a "Hello World" on Android...` | ✅ | ✅ | ✅ |
| what is a JNI hook | `L ×\n\nIn the context of Android game modding...` | ✅ | ✅ | ✅ |

That is the Phase 4 acceptance criteria, satisfied against a live endpoint.

---

## What is running

```
Modal container (8 CPU cores, 32 GiB, no GPU)
├── llama-server  127.0.0.1:8081   GLM-4.7-Flash-Q4_K_M.gguf  18.31 GB
└── FastAPI gateway  0.0.0.0:8000  ← only this is public
        • injects the system prompt if absent
        • bearer auth (leaks 401 without the key)
        • streams SSE straight through
```

llama.cpp is built from source inside the image, so there's no dependency on a
prebuilt registry that might vanish.

## Measured performance

| | |
|---|---|
| model load | **31 s** |
| short reply | **~9 s** includes prompt processing |
| sustained generation | **~11.96 tok/s** (299 tokens in 25 s) |
| cold start | ~40 s total (container + model) |

Roughly 3–5× slower than typing speed for reading, but it's a real 30B model on
CPUs you aren't paying for.

## Cost

```
Modal GPU    BLOCKED — "Please add a payment method to use T4 GPU functions."
Modal CPU    OK
2 cores + 4 GiB = $0.127/hr  ->  $30/mo ≈ 237 CPU-hours
idle (scaledown_window=300)  = $0
```

8 cores × ~$0.0473 + 32 GiB × $0.008 ≈ **$0.63/hr while awake**, then it stops.
That's roughly **45 hours/month** of awake time inside the $30 credit.

GGUF weights live on the `levi-models` volume, so only the first boot pays the
18 GB download.

---

## Gotchas that cost real deploy cycles — do not undo these

1. **`GGML_NATIVE=OFF` is mandatory.** The image builds on one CPU and runs on
   another. A native build dies instantly with `rc=-4` (SIGILL) and *no error
   message* — it just prints "initializing ..." and vanishes. Keep
   `-DGGML_BACKEND_DL=ON -DGGML_CPU_ALL_VARIANTS=ON`.
2. **The prompt ships as a FILE, not an env var.** It contains an apostrophe,
   which breaks the generated Dockerfile `ENV` line and fails the build.
3. **`levi_app.py` must not hard-require the prompt file.** Modal re-imports the
   module inside the container where only `add_local_file` paths exist. It's
   wrapped in `try/except OSError` on purpose.
4. **`llama-server --system-prompt` does not exist in this build.** No
   `--api-key` either. That's why there's a gateway.
5. **Edge-cached images ignore prompt-only changes.** `modal deploy` said "no
   changes detected" while serving the old prompt. To force a refresh:
   ```bash
   modal app stop levi -y && modal deploy levi_app.py
   ```
   Then confirm `prompt_chars` actually moved.

## Updating the prompt from now on

```bash
# 1. edit modal/levi-system-prompt.md
wc -c modal/levi-system-prompt.md          # note the number
modal app stop levi -y && modal deploy modal/levi_app.py
curl <URL>/health                          # prompt_chars must equal that number
```

Two commands plus a check. No base64, no kernel versions, no re-push.

## Speed knobs, in order of payoff

| change | effect |
|---|---|
| `QUANT = "Q3_K_M"` (14.61 GB) | less memory traffic, maybe +20–30% tok/s |
| `THREADS = 16` | more cores, ~2× cost, maybe +40% tok/s |
| `CTX = 4096` | smaller KV cache, marginal |
| add a card, `gpu="T4"` + smaller GGUF | **~10× faster**, but that's paid |

---

## Files
- `levi_app.py` — Modal app
- `levi_gateway.py` — FastAPI gateway (prompt injection, auth, streaming)
- `levi-system-prompt.md` — the server-side prompt, verbatim
- `opencode.jsonc` — ready to drop in; paste the key

## Retired
`levi_serve.py`, `README.md` (vLLM/GPU plan), `SETUP.md` (GPU setup) — kept for
reference, superseded. The GPU route needs a payment method.
