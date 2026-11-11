# Levi — restart steps

The prompt is already saved on Kaggle (version 3, 1,906 chars,
`# Levi -> Activated 🫟!`). It is not running yet. This is the whole situation in
one page.

---

## Why it cannot start right now

```
$ kaggle kernels push -p .
Kernel push error: Maximum batch GPU session count of 2 reached.
```

That message is misleading. Every one of your kernels is `COMPLETE` — nothing is
holding a session. The real reason is **GPU quota is used up**:

```
gpuQuota:
   used      29h38m
   reserved  11h18m
   allowed   30h00m
   remaining     21m      <- cannot start a T4 session
   resets    2026-11-14T00:00:00Z
```

A T4 session reserves hours upfront. With 21 minutes left, Kaggle refuses, and
reports it as a session-count error.

I also tried a CPU-only run (`enable_gpu: false`) — same error, because the
account's batch-session budget is exhausted either way. It is not a code problem.

---

## Steps, when quota resets

Quota resets **2026-11-14 00:00 UTC**. Then:

### 1. Start the kernel

```bash
kaggle kernels push -p .        # from a folder containing the notebook + metadata
```

Or from the web UI: open the notebook and press **Run All**.

### 2. Read the two values it prints

The first output block contains:

```
  BASE URL   https://<random>.trycloudflare.com/v1
  API KEY    levi-<random>
```

Both change on every run. Nothing else will work until you copy them.

### 3. Confirm the new prompt is live

```bash
curl -s "$BASE/v1/chat/completions" -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"glm-4.7-flash","messages":[{"role":"user","content":"say ready"}],"max_tokens":40}'
```

- Old prompt is still running if you see `LEVI -> Levi Assistant Active 🧬`
- New prompt is live if you get the `Levi -> Activated` behaviour

### 4. Point opencode at the new URL

In `~/.config/opencode/opencode.jsonc`:

```jsonc
"settings": {
  "baseURL": "http://127.0.0.1:8899/v1",   // if using the proxy
  "apiKey":  "levi-<new key>"
}
```

Or the tunnel URL directly if you drop the proxy.

If you are using `levi-proxy.py`, restart it with the new upstream:

```bash
python ~/levi-proxy.py --upstream "https://<new>.trycloudflare.com/v1" \
  --port 8899 --strip-canned --no-replace \
  --inject-user ~/levi-system-prompt.md
```

With the new prompt live, `--inject-user` and `--strip-canned` become optional —
the server stops emitting the old header on its own.

### 5. Stop rotating the API key

Add `LEVI_API_KEY` as an environment variable or Kaggle secret in the notebook
settings. Without it, the key is regenerated every run and step 4 repeats.

---

## To avoid this next time

An interactive session has an idle timeout (about 12h on a T4). `levi-coder` was
left running and burned ~12 hours of reservation past the point of use, which is
what put the account at 29h38m of 30h.

Stop the session when you are done for the day. `kaggle kernels status` tells you
if it is still `RUNNING`; there is no stop command in the CLI, so use the
**Stop Session** button on the notebook page.
