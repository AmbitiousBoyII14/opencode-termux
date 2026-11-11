# Restarting levi-coder

The saved prompt is already updated (version 3). The running session is not.
Pushing cannot fix that, and here is why.

## The blocker

```
$ kaggle kernels push -p .
Kernel push error: Maximum batch GPU session count of 2 reached.
```

That is not a code error — the code is fine and version 3 saved cleanly
(`--no-run`). Kaggle is refusing to start a *new* GPU session because the account
already holds two:

- the live `levi-coder` session (interactive, has a T4)
- a second batch slot already reserved

A pushed run is a **batch** job. It needs a free GPU slot, and there is none. So
the push keeps bouncing, and the old process keeps serving the old prompt.

## Quota at the time of writing

```
resets       2026-11-14T00:00:00Z
GPU used     28h24m
GPU reserved 11h55m     <- levi-coder, still alive
GPU allowed  30h00m
remaining    1h35m
```

Also relevant: an interactive session has an idle timeout (roughly 12h on a T4).
`levi-coder` is holding ~11h55m of reservation, so it is close to that ceiling and
will be reaped on its own soon-ish, but not on demand.

## The one action that unblocks it

**Stop the session from the Kaggle UI.** There is no API for it — I probed
`/stop`, `/interrupt`, `/cancel`, `/shutdown`, `/session` on both the kernel and
the push resource; all 404.

1. Open <https://www.kaggle.com/code/syamthandasawoni/levi-coder>
2. Top right: **Stop Session** (or *Session → Stop*)
3. Then run:

```bash
kaggle kernels push -p .        # starts fresh, picks up version 3
```

## After it restarts

Two values change every run:

| what | why | where it goes |
|---|---|---|
| `BASE URL` | cloudflared assigns a new `trycloudflare.com` hostname each run | `baseURL` in `~/.config/opencode/opencode.jsonc`, and `--upstream` for `levi-proxy.py` |
| `API KEY` | `"levi-" + secrets.token_hex(20)` unless `LEVI_API_KEY` is set in the kernel env | `apiKey` in the same file |

Both are printed in the first block of output. To stop the key rotating, add
`LEVI_API_KEY` as an environment variable or Kaggle secret.

Then confirm the new prompt is live before touching the phone:

```bash
curl -s "$BASE/v1/chat/completions" -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"glm-4.7-flash","messages":[{"role":"user","content":"say ready"}],"max_tokens":40}'
```

Expected: a reply starting with `# Levi -> Activated` behaviour — **not**
`LEVI -> Levi Assistant Active 🧬`.
