# Levi: where the persona actually comes from

## It is not a prompt. It is a post-processor.

This is the thing I got wrong for three turns, so here is the proof.

Ask the model for one word:

```bash
curl -s "$BASE_URL/v1/chat/completions" -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"glm-4.7-flash","messages":[{"role":"user","content":"Reply with the single word BANANA and nothing else."}],"max_tokens":60}'
```

```json
{"content": "LEVI -> 🍌"}
```

The word came back **replaced by an emoji**. No language model does that — it is
running after the model finishes, on the server, rewriting `BANANA` into `🍌` and
bracketing it with the `LEVI ->` header.

Evidence it is not prompt-level:

| what I sent | what came back | conclusion |
|---|---|---|
| `"Always answer in French"` as a system message | English answer | system message ignored |
| `"Answer in French"` in the user message | English answer | user message ignored |
| `AGENTS.md` in the project | still the canned block | opencode instructions ignored |
| `"Reply with the single word BANANA"` | `LEVI -> 🍌` | output is rewritten |

Every channel a client has fails, because the model never writes the header. It is
added to the response afterwards.

**To change it at the source**, edit the middleware/server-side prompt where `LEVI`
is defined. Nothing shipped in a config file can win that race.

---

## Your endpoint runs its own agent

This is the thing that explains everything else. The server ignores the request
shape and runs its own agent loop with its own tools:

```
Levi 👾 -> Activated 👾!
(stopped after 6 tool rounds)
⟢ run_command {"cmd": "cd /tmp && git clone --depth 1 https://github.com/LGLTeam/... "}
```

opencode sent no tools at all. The server added them, ran them on its own machine,
and capped itself at 6 rounds. It also ignores the `system` role, which is why
every prompt I gave you did nothing.

**What does work: the user role.** The same prompt appended to the first user
message is obeyed — tested, it read both repos. That is what `--inject-user` does.

## The fix that works without server access: `levi-proxy.py`

A small local proxy that strips the header from the stream and replaces it with
yours. It is stateless and forwards everything else untouched.

### On Termux

```bash
pkg install python
```

Terminal 1 — run the proxy:

```bash
python ~/levi-proxy.py \
  --upstream "https://your-host/v1" \
  --port 8899 \
  --strip-canned \
  --inject-user ~/levi-prompt.txt
```

Terminal 2 — point opencode at it. In `~/.config/opencode/opencode.jsonc`:

```jsonc
"settings": {
  "baseURL": "http://127.0.0.1:8899/v1",
  "apiKey": "anything"          // the proxy forwards your real Authorization header
}
```

Then `opencode` as normal.

### Options

| flag | effect |
|---|---|
| `--header "..."` | replacement first line (default `Levi 👾 -> Activated 👾!`) |
| `--strip-canned` | also drop the "Awaiting target specification." + numbered list |
| `--no-replace` | remove the header, inject nothing |
| `--inject-user FILE` | prepend FILE to the first user message — **required**, because the server ignores the system role |
| `--port` | default 8787 |

---

## What I could and could not verify

**Verified, against your live endpoint, through the proxy:**

```
in : "Say hello in one short sentence."     (streamed)
out: "Levi 👾 -> Activated 👾!\n\nHello."
```

Three consecutive streamed runs, clean — your header present, `LEVI -> 🔎` gone.
Non-streaming responses likewise.

**Could not verify: opencode → proxy end to end.** From this sandbox, opencode
fails against your endpoint with `ECONNRESET` whether or not the proxy is in the
path, and against the direct upstream too:

```
opencode -> proxy -> upstream    ECONNRESET
opencode -> upstream             ECONNRESET
curl     -> proxy -> upstream    200
```

So the proxy is not the cause; your server is rejecting opencode's request shape
when it comes from here. On your phone opencode clearly *does* connect (your
screenshots show real replies), so the proxy should work there. If it does not,
send me the proxy's terminal output — it prints the upstream error it gets.

---

## Correction to what I said earlier

I told you a system message removed the header. That was one sample out of one,
and it was wrong. Five consecutive identical runs with that same system message
kept the header 5/5. Your screenshot is the ground truth: no client-side prompt
changes it.

---

## Still true

Your endpoint declares no context length, so opencode assumes 200,000 against a
real 32,768 window and reserves 16,000 tokens (49%) before you start. Separately,
`(stopped after 1 tool round)` is the server's own `content` field, not opencode:

```json
{"finish_reason": "tool_calls",
 "message": {"content": "(stopped after 1 tool round)", "tool_calls": [...]}}
```

`opencode.jsonc` fixes the window. The tool-round cap is server-side.

---

## Current server prompt (replacement)

`levi-system-prompt.md` is the text to put in the server-side system prompt, at
whatever place `LEVI -> Levi Assistant Active` is defined. That is the only place
the header and the one-round cap can be removed at the source.

If you would rather not touch the server, the proxy delivers the same text through
the user role, which the server does obey:

```bash
python ~/levi-proxy.py --upstream "https://your-host/v1" --port 8899 \
  --strip-canned --no-replace \
  --inject-user ~/levi-system-prompt.md
```

`--no-replace` is deliberate: this prompt tells the model to open with its own
banner, so the proxy should not add another. It still removes the server's
`LEVI -> ...` line wherever it lands near the top of a reply — verified:

```
in : "say ready"
out: "L ×\n\nReady."
```

### One note on the emoji

`🫟` is U+1FADF, which Unicode leaves **unassigned**. It will render as a blank box
on most devices. Nearby assigned options if you want one that renders: 🫠 🫡 🫧 🫨.
Left as written in `levi-system-prompt.md`, since that is your text.
