# Modal — VERIFIED STATUS 2026-11-11

## GPU is blocked until a card is on file

```
modal run smoke.py   ->  InvalidError: Please add a payment method to use A10G GPU functions.
modal run smoke2.py  ->  InvalidError: Please add a payment method to use T4 GPU functions.
modal run smoke3.py  ->  CPU -> x86_64 cores=17        [works]
```

Modal's published "no card on Starter" claim does **not** hold for GPU
functions. Credentials are valid, workspace is `syamthandasawoni`, billing
reads `$0.00`, CPU runs fine — only GPU allocation is gated.

**So `$30/mo of free GPU` is not currently reachable.** Not a config problem.
A payment method has to be added in the dashboard, or this route is closed.

### Verified rates (from `modal billing rates`, this workspace)
```
T4       $0.59/hr      L4      $0.80/hr      A10G   $1.10/hr
L40S     $1.95/hr      A100-40 $2.10/hr      A100-80 $2.50/hr
CPU      $0.0473/core/hr       Memory  $0.008/GiB/hr
```
2 cores + 4 GiB = **$0.127/hr** → $30 stretches to ~237 CPU-hours.

### Verified model sizes
```
zai-org/GLM-4.7-Flash       62.5 GB   fp8, transformers, NOT gated, MIT
unsloth ...Q4_K_M.gguf      18.31 GB  best quality that fits 24 GB
unsloth ...IQ4_XS.gguf      16.27 GB  fits 16 GB card, nearly
unsloth ...UD-Q3_K_XL.gguf  13.78 GB  safe on a 16 GB T4
```

---

# Modal — getting the API, and the honest numbers


## Do you need to send me anything? No.

Modal gives you a **URL + API key**. I don't need your account login, and you
shouldn't paste a Modal token into chat — a token can spend your credits.

You paste the endpoint into `opencode.jsonc` yourself. That's it.

---

## Colab: is it lifetime free?

**The product is free forever. The GPU is not.**

| | Free Colab |
|---|---|
| Cost | $0, indefinitely |
| GPU | T4, **16 GB** |
| Availability | **not guaranteed** — "varies over time" |
| Session max | ~12 h |
| Idle disconnect | ~90 min |
| Background execution | Pro+ only ($49.99) |
| Usage limits | can hit after **30 min** of GPU, recovery **up to 5 days** |

Two hard blockers for you, independent of the flakiness:

1. **16 GB T4 vs 19 GB of weights.** `glm-4.7-flash` doesn't fit. Not "fits
   slowly" — it doesn't load.
2. **Colab is a notebook, not a server.** You'd have to keep the tab open, and
   the URL is not stable. Same trap as Kaggle, with a worse GPU.

So: free forever as a product, useless for this model.

---

## Modal: getting the endpoint

### 1. Sign up — no card
<https://modal.com/signup> → "Continue with GitHub". `$30` credits appear the
moment your workspace exists. No application, no waitlist.

### 2. Install the CLI
```bash
python3 -m pip install modal
python3 -m modal setup
```
Opens a browser, writes the token to `~/.modal.toml`.

### 3. Store the API key you want the endpoint to require
```bash
python3 -m modal secret create levi-secret LEVI_API_KEY=levi-$(openssl rand -hex 20)
```
Copy that key somewhere — you'll put it in `opencode.jsonc`.

### 4. Confirm the model repo exists
```bash
curl -s https://huggingface.co/api/models/zai-org/GLM-4.7-Flash | head -c 300
```
If it 404s, swap `MODEL_REPO` in `levi_app.py` for the right org name. This is
the one value in the file I could not verify from here.

### 5. Deploy
```bash
modal deploy modal/levi_app.py
```
First boot downloads ~19 GB of weights onto the volume (~5–8 min). It prints a
URL like `https://xxxxx--levi-serve.modal.run`.

### 6. Check it
```bash
curl https://xxxxx--levi-serve.modal.run/v1/models \
  -H "Authorization: Bearer $LEVI_API_KEY"
```

### 7. Point opencode at it
```jsonc
{
  "provider": {
    "modal": {
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "https://xxxxx--levi-serve.modal.run/v1",
        "apiKey": "levi-..."
      },
      "models": { "glm-4.7-flash": { "name": "Levi" } }
    }
  }
}
```

---

## The cost reality — read this bit

| | Kaggle | Modal |
|---|---|---|
| Free pool | 30 GPU-h / **week** (~120 h/mo) | **$30/mo** |
| GPU | 2× T4 = **30 GB** | A10G = **24 GB** |
| In hours | ~120 h/mo | **~27 h/mo** |
| Scale to zero | no — burns while idle | yes |
| URL | new `trycloudflare` every restart | **stable** |
| Prompt update | re-push kernel, wait for reboot | edit file, redeploy |

Modal is **less GPU time** than Kaggle. What you get for it: no quota cliff,
no 6-day lockout, a stable URL, and a prompt that lives in a file you can grep.

If you talk to it more than ~27 hours a month, you'll need to top up. For normal
coding sessions, 27 hours is a lot more than it sounds — 5 minutes of idle scales
to zero instead of burning quota.

### Cheaper GPUs on Modal, same 24 GB
Modal lists **L4** and **A10** in the same price band or below the A10G. If
`A10G` pushes the bill, try `GPU = "L4"` in `levi_app.py` — 24 GB, newer
architecture, typically lower per-hour. Compare in the Modal pricing page; the
model fits either way.

---

## Files here
- `levi_app.py` — the whole endpoint
- `levi-system-prompt.md` — your prompt, verbatim. **This is the server-side
  prompt now.** Edit it, redeploy, done. No base64, no kernel versioning.
