# The prompt is server-side, in a Kaggle notebook

The endpoint is a Kaggle kernel serving Ollama behind a cloudflared tunnel. The
persona is **not** middleware — it is `PROMPT_B64` in the kernel source.

## Where it lives

```
kernel    syamthandasawoni/levi-coder
file      levi-coder.ipynb
variable  PROMPT_B64 = "<base64 of the markdown prompt>"
used at   system = LEVI_SYSTEM if kind == "levi" else CODER_SYSTEM
```

Decoded, the old prompt was 14,683 characters ("LEVI v3.0 — OPERATOR") and
contained the header rule directly:

```
### Header — every reply, line 1

LEVI -> {ICON}
```

That is where `LEVI -> 🔎` came from. Not middleware, not the model's habit.

## How to change it

```bash
kaggle kernels pull syamthandasawoni/levi-coder -p . -m
# decode PROMPT_B64, replace it, re-encode
kaggle kernels push -p .
```

`levi-system-prompt.md` in this folder is the replacement that was pushed.

## The catch: a push does not restart a running session

`kaggle kernels push` saves a new version. A kernel that is already RUNNING keeps
serving the **old** prompt from memory — verified: after the push, three requests
still returned `LEVI -> Levi Assistant Active 🧬`.

To make it live:

1. **Stop** the running session (Kaggle UI → Stop Session, or `kaggle kernels
   status` then stop).
2. Re-run the notebook.
3. It prints a **new** `BASE URL` — `trycloudflare.com` assigns a fresh hostname
   every run.
4. Update `baseURL` in `~/.config/opencode/opencode.jsonc`, and the `--upstream`
   flag if you are using `levi-proxy.py`.
5. The API key survives only if `LEVI_API_KEY` is set in the kernel environment.
   Otherwise a new one is generated and printed at startup.

## Everything else in that notebook, for reference

| thing | where | notes |
|---|---|---|
| tool-round cap | `return "(stopped after %d tool round%s)"` | the string you kept seeing; the loop `break`s when a tool is external |
| model list | `MODELS` | one entry: `glm-4.7-flash:latest`, `num_ctx` 32768 |
| tools | `tool_list/read/run/grep/elf/hash/carve` | server-side; the client's tools are ignored |
| tunnel | `cloudflared tunnel --url http://127.0.0.1:PORT` | URL parsed from `tunnel.log` |
| routes | `/health /vram /events /upload /v1/models /v1/chat/completions /chat` | no prompt read/write route |
