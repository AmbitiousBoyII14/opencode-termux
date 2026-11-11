# Why it acts like that, and what actually helps

Two separate problems got blamed on one thing. Only one of them is opencode's.

---

## 1. The `LEVI -> 🔎` header is your endpoint, not opencode

Proof — raw `curl`, no opencode in the loop:

```bash
curl -s "$BASE_URL/v1/chat/completions" \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"model":"glm-4.7-flash","messages":[{"role":"user","content":"Reply with exactly: raw test"}],"max_tokens":50}'
```

```json
"content": "LEVI -> \ud83d\udd0e\n\nraw test"
```

The model server prepends it before it ever sees opencode. Whatever opencode
sends, the header comes back.

**But a system message does remove it.** Same `curl`, with one added message:

```bash
-d '{"model":"glm-4.7-flash","messages":[
      {"role":"system","content":"Never write any name, arrow, or emoji header. Answer with the bare result only."},
      {"role":"user","content":"Reply with exactly: sys test"}]}'
```

```json
"content": "sys test"
```

So the fix works — it just has to arrive as a real system message.

### The catch: `agent.<name>.system` does not arrive

I put the rules in `agent.build.system` and they were accepted without error but
never reached the model — the header kept appearing. The same happens for a
`prompt` key. Do not rely on either.

`AGENTS.md` **is** read into session context (`packages/core/src/tool/plugin/read.ts`,
`instance.ts`), so that is where the rules belong. I could not finish verifying it
end-to-end because your endpoint started resetting connections partway through
testing — so treat this as the documented mechanism rather than something I proved
on your box.

**Where to put it:** copy `AGENTS.md` from this folder to your project root, or to
`~/.config/opencode/AGENTS.md` for all projects.

---

## 2. Its context window is 32,768 but opencode assumed 200,000

This one is real and it is opencode's. From `packages/core/src/session/compaction.ts`:

| constant | value | on a 32,768 window |
|---|---|---|
| `RESERVE_MIN` | 16,000 | **49% of the window reserved before you start** |
| `RESERVE_SHARE` | 0.15 | 4,915 — `RESERVE_MIN` wins |
| `SUMMARY_OUTPUT_FLOOR` | 32,000 | as large as the whole window |
| `UNKNOWN_WINDOW` | 200,000 | what it assumes when the model declares nothing |

Your `/v1/models` response returns only `id`, `object`, `created`, `owned_by`,
`description` — **no context length**. So opencode falls back to its default and
mismanages the window. That produces the behaviour in your screenshots: one tool
call, a compressed reminder, and a request to re-ask.

`opencode.jsonc` in this folder declares `limit.context: 32768` so the maths uses
the real number.

---

## 3. `usage` reports `prompt_tokens: 0`

```json
{"prompt_tokens": 0, "completion_tokens": 108, "total_tokens": 108}
```

Your endpoint does not report prompt tokens. opencode estimates instead, and its
compaction logic is built on those estimates. Expect the compaction trigger to be
approximate. If you control the server, this is worth fixing — it is a
one-line change on the serving side and it improves every client, not just this one.

---

## 4. The endpoint is not reliable under opencode's request size

During testing, plain small requests returned `200` in ~0.2 s, repeatedly, while
opencode's requests — with full tool schemas — got `ECONNRESET`, and at the end
`ECONNREFUSED`. A 3,000-token system prompt sent by hand succeeds, so it is not
raw size; it looks like the tool-schema payload or concurrency.

That is a server-side limit, not something a config change can paper over. If
`opencode` fails while `curl` works, this is why.

---

## Install

```bash
mkdir -p ~/.config/opencode
cp opencode.jsonc ~/.config/opencode/opencode.jsonc     # edit baseURL + apiKey
cp AGENTS.md ~/your-project/AGENTS.md                   # or ~/.config/opencode/AGENTS.md
```

Restart `opencode` — config is read at startup.
