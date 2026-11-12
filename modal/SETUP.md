# Modal setup — the version that works from Termux

## Read this first: don't run the CLI on your phone

`pip install modal` **fails on Termux (aarch64/Android)**. Modal depends on
`grpcio`, which has no Android wheel and fails to compile:

```
ERROR: Failed building wheel for grpcio
ERROR: Failed to build installable wheels for some pyproject.toml based projects (grpcio)
```

That's a known, open, unsolved issue — people have been fighting it since 2023
and it still fails as of late 2026. There's no flag combo that fixes it.

**Good news: you don't need the CLI on the phone.** The CLI only deploys. The
*endpoint* it deploys is a public HTTPS URL that works fine from Android. So:

> deploy from a laptop / desktop / any Linux box / GitHub Codespaces.
> opencode on the phone just points at the URL afterwards.

---

## Path A — deploy from a computer (recommended)

### 1. Sign up
<https://modal.com/signup> → **Continue with GitHub**. No credit card.
`$30` credits appear as soon as the workspace exists.

### 2. Create a token
Dashboard → **Settings → API Tokens** → **New Token**.

You get two strings:
- an **ID** starting `ak-`
- a **secret** starting `as-`

Copy both. You'll paste them once.

### 3. Install the CLI
```bash
python3 -m pip install modal
python3 -m modal --version
```

### 4. Authenticate
```bash
python3 -m modal token set --token-id ak-XXXXXXXX --token-secret as-YYYYYYYY
```
Non-interactive, no browser. It writes `~/.modal.toml`.
Equivalent if you prefer env vars (they override the file):
```bash
export MODAL_TOKEN_ID=ak-XXXXXXXX
export MODAL_TOKEN_SECRET=as-YYYYYYYY
```
> Avoid `modal token new` / `modal setup` if a browser is awkward — those are the
> one-time interactive sign-in. `token set` is the paste-it-in route.

### 5. Verify
```bash
python3 -m modal whoami
# -> Authenticated as <you> for workspace <name>
```

### 6. Store the endpoint's API key
This is the key opencode will send. Different thing from the Modal token above.
```bash
python3 -m modal secret create levi-secret LEVI_API_KEY=levi-$(openssl rand -hex 20)
```
Keep that key — it goes in `opencode.jsonc`.

### 7. Confirm the model repo name
```bash
curl -s https://huggingface.co/api/models/zai-org/GLM-4.7-Flash | head -c 200
```
404? Fix `MODEL_REPO` at the top of `levi_app.py`. This is the only value I
couldn't verify from here.

### 8. Deploy
```bash
modal deploy modal/levi_app.py
```
First boot downloads ~19 GB of weights to the volume. 5–10 min. You get:
```
https://xxxxx--levi-serve.modal.run
```

### 9. Check it
```bash
curl https://xxxxx--levi-serve.modal.run/health
# -> {"ok":true,"prompt_chars":1906,"upstream":"http://127.0.0.1:8001"}
```
`prompt_chars` should match `wc -c levi-system-prompt.md`. If it's 0, the prompt
didn't bake in — stop and tell me.

Then the real test:
```bash
curl https://xxxxx--levi-serve.modal.run/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $LEVI_API_KEY" \
  -d '{"model":"glm-4.7-flash","messages":[{"role":"user","content":"say ready"}]}'
```

---

## Path B — no computer? Use GitHub Codespaces

Free tier gives you a Linux box in the browser. On your phone:

1. GitHub → **Code** → **Codespaces** → **Create codespace**
2. In its terminal: steps 3–9 above, unchanged
3. Copy the `modal.run` URL out

A bit clumsy on a phone keyboard, but it's a real Linux shell with a working
`grpcio`.

---

## Path C — try it on the phone anyway (expect failure)

If you want to confirm for yourself:
```bash
pkg install python binutils clang libc++ rust
pip install modal
```
It will fail on `grpcio`. Some people get past it by downloading the
`linux-aarch64` `grpcio` wheel from PyPI and dropping the `.so` into
site-packages — that wheel is glibc-linked and Termux is bionic, so it usually
breaks at import with a symbol error. Not worth the afternoon. Use Path A or B.

---

## Files
- `levi_app.py` — Modal app: vLLM on :8001, gateway on :8000
- `levi_serve.py` — the gateway. Injects your system prompt, streams back.
- `levi-system-prompt.md` — your prompt, verbatim. **This is the server-side
  prompt now.** Edit it, redeploy, done.
