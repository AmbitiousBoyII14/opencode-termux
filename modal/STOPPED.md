# STOPPED — workspace spend limit hit 2026-11-12

## What happened

```
POST /v1/chat/completions  (11376-token prompt)
  -> context exceeded 8192          (my bug: CTX was too low)

  after the CTX=32768 redeploy:
  -> "modal-http: internal error: function was terminated by signal"
  -> "modal-http: workspace ac-OIDpev85SjWCSyr6MVF3uR is disabled"

modal run ping.py
  -> Workspace ac-OIDpev85SjWCSyr6MVF3uR has exceeded its spend limit
```

The workspace is **disabled**. Not a config problem, not a code problem. Every
call returns that error, deploys included. Only the Modal dashboard can lift it.

## Why the limit was reached

`modal billing summary`:
```
Metered Cost:   $1.06
Credits:        $1.00
Billed Cost:    $0.06
```

That `Credits: $1.00` is the whole story. This account had **$1.00 of credit,
not $30**. The "$30/mo free tier" is what Modal advertises for Starter plans; it
did not apply here. There is no payment method on the workspace, so spend
hard-stops at the credit balance.

Where the money went — `modal billing report --show-resources`:

| what | why | ~cost |
|---|---|---|
| bench / diag apps | llama.cpp rebuilds, SIGILL diagnosis, perf runs | **$0.90** |
| the live endpoint | ~2 h of 8-core serving with idle time | $0.13 |

The debugging was the expensive part, not the serving.

---

## The actual bug the user hit

Screenshot: `400 Exceed_context_size_error: Request (8305 tokens) exceeds the
available context size (8192 tokens)`.

Cause: client sends **8305 tokens of system prompt** for a one-word message.
Server was started with `-c 8192`. My configuration error.

Math for the fix (from `config.json`: 47 layers, 20 KV heads, head_dim 128, fp16):

| ctx | KV cache | + 18.31 GB model |
|---|---|---|
| 8192 | 3.14 GB | 21.45 GB |
| 16384 | 6.28 GB | 24.59 GB |
| 32768 | 12.57 GB | **30.88 GB** |

30.88 GB does **not** fit in the 32 GiB the function was given. That's why the
first 32K attempt died with "terminated by signal" — OOM, before spend limits
were the issue.

The redeploy that raised `memory=32768 -> 65536` and `CTX=8192 -> 32768` never
took effect in a live container: the workspace was disabled during the test.

---

## To bring it back

1. Modal dashboard -> Settings -> Billing -> add a payment method.
   This both lifts the spend limit and makes the $30/mo Starter credit apply.
2. Then, from a machine with the CLI:
   ```bash
   modal deploy modal/levi_app.py
   curl <URL>/health     # prompt_chars must be 1875
   ```
3. Current source already has the fixes staged:
   - `CTX = 32768`
   - `memory=65536`
   - `--cache-reuse 256`

   The `--cache-reuse` flag matters more than it looks: the client resends the
   same ~8.3k system prefix every single turn. Reusing it turns each turn's
   prefill from ~60 s into near zero.

## Without adding a card

The endpoint is gone. Nothing in the Modal free-without-card tier will serve a
19 GB model from here on.

Fallbacks, unchanged in priority:

1. **Kaggle** — resets 2026-11-14T00:00Z. 2x T4 = 30 GB, free, no card, handles
   the 8.3k system prompt without complaint. Notebook is saved as version 3.
2. **Groq / Google AI Studio** — no card, works today, but serves *their* models.
   Your prompt works; it just won't be GLM-4.7.
3. **Client-side trim** — if the client's 8305-token system prompt is something
   you control, shrinking it is the cheapest fix of all. At 8k ctx the model was
   functional; the prompt was the thing that didn't fit.

## Still true

- The deployment itself worked: `L ×` opener, 4/4 acceptance pass, ~12 tok/s,
  31 s model load, prompt served server-side at 1875 chars.
- The prompt bug (`RESPONSE SAME WHEN THINKING` being echoed into replies) was
  found and fixed.
- API key `levi-4bb…` and the `modal.run` URL are both dead now.
