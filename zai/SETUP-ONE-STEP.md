# One command. That's it.

Open Termux and paste this:

```sh
curl -fsSL https://raw.githubusercontent.com/AmbitiousBoyII14/opencode-termux/main/zai/install.sh | sh
```

Wait. It ends by printing:

```
===================================================
 WORKING. model said:
   L × Ready
===================================================
```

If you see `L ×`, you're done. Open opencode — Levi is already selected.

---

## What that command actually did

Nothing scary. It ran a 100-line shell script that:

1. checked `python3` exists (installs it if not)
2. downloaded 2 files into `~/zai`
3. put your API key in `~/zai/zai-key.txt`
4. wrote `~/.config/opencode/opencode.json` (backing up any existing one)
5. started the proxy in the background
6. asked it "say ready" and printed the answer

You can read the whole thing before running it:
<https://github.com/AmbitiousBoyII14/opencode-termux/blob/main/zai/install.sh>

---

## If something goes wrong

**"no reply" / timeout**
The free tier is busy. Try again:
```sh
curl -s localhost:8080/health
```

**"connection refused" in opencode**
The proxy isn't running. Start it:
```sh
cd ~/zai && nohup python3 zai-proxy.py > zai.log 2>&1 &
```

**Empty replies from the model**
Thinking got re-enabled. The proxy disables it automatically — if you see
empty strings, check you're pointing at `127.0.0.1:8080` and not `api.z.ai`
directly.

**Everything is broken, start over**
```sh
pkill -f zai-proxy.py; rm -rf ~/zai
```
then run the one command again. It's safe to re-run any number of times.

---

## The three facts you need to remember

**1. The proxy must be running.**
It's the thing between opencode and Z.ai. If your phone reboots, it's gone.
Restart with the `cd ~/zai && nohup ...` line above.

**2. Replies take 30–60 seconds.**
That's the free tier, not a bug. Half of first attempts get retried
automatically. Be patient on the first message of a session.

**3. It's free because it's shared.**
No card, no quota, no bill. The trade is speed and the occasional retry.

---

## What this replaced

Kaggle GPU (quota locked until Nov 14), Modal GPU (needed a card),
Modal CPU ($1 credit, now exhausted). All three dead ends.

Z.ai serves **GLM-4.7-Flash — your exact model** — free, with **128K context**
instead of the 8K that was breaking things. That's why this is the one that stuck.

---

## Files

| file | what it is |
|---|---|
| `zai-proxy.py` | the proxy. stdlib only, no pip needed |
| `levi-system-prompt.md` | your prompt, 1875 chars, injected server-side |
| `zai-key.txt` | your API key (chmod 600) |
| `install.sh` | the one-command installer |

On your phone after install: `~/zai/` and `~/.config/opencode/opencode.json`.
