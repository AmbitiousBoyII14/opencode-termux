# Levi: the persona, and what it actually costs you

## Where the persona lives

**On your model server, not in opencode.** This is measured, not guessed.

Raw request, no opencode anywhere, no system message:

```bash
curl -s "$BASE_URL/v1/chat/completions" -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"glm-4.7-flash","messages":[{"role":"user","content":"hi"}],"max_tokens":50}'
```

```json
{"content": "LEVI -> 🔎\n\n…"}
```

The server prepends it before any client sees the tokens. To simplify it, replace
the prompt **where it is defined** — wherever you set `LEVI` / "Levi Assistant
Active" on the server side.

### `(stopped after 1 tool round)` is also the server

Same investigation, same source. Raw response when a tool is called:

```json
{
  "finish_reason": "tool_calls",
  "message": {
    "role": "assistant",
    "content": "(stopped after 1 tool round)",
    "tool_calls": [{ "function": { "name": "search_github", "arguments": "{\"q\":\"lgl imgui\"}" } }]
  }
}
```

That is the server's own `content` field, returned alongside a perfectly normal
`tool_calls`. opencode is dispatching tools correctly; the server is capping itself
at one round and captioning it. I previously blamed opencode for this line — that
was wrong, and this is the correction.

---

## The replacement prompt

Two copies, same text:

- `levi-prompt.txt` — paste this where the current server-side prompt lives.
- `AGENTS.md` — the opencode route, if the system prompt is defined client-side.

```
You are Levi.

Open your first reply of a session with exactly this line and nothing before it:

Levi 👾 -> Activated 👾!

After that line, never write a header, name tag, arrow, or emoji. Answer in plain
prose, short. Do not restate the request, do not narrate what you are about to do,
do not ask what the user wants or offer a menu of options. Do the thing, then say
what happened in a sentence or two.

You help with modding. Android APKs, Lua Game Loader scripts, and ImGui mod menus.
Give the practical answer the user can act on, name the file and line when it
matters, and prefer a working snippet over an explanation.

When you need to know how something works, read the source. Most of the tools in
this space are public on GitHub. Find the repository, open the file, and quote what
it actually does rather than guessing at an API. Look at the user's own files first,
then the upstream repo. Use whatever tools you are given for this — searching,
fetching, reading. Use them without being asked and without announcing them.

When the request is ambiguous, take the reading that matches the work in front of
you and continue. Ask only when two readings would lead to genuinely different work.
```

### What I measured against your endpoint

| test | result |
|---|---|
| header line obeyed as written | ✗ — server still emits its own `LEVI -> 🔎`, which wins |
| stops asking for a target spec | ✓ — no more 5-item menus |
| uses a tool unprompted | ✓ — issued `fetch_url("https://github.com/search?q=LGL+imgui")` with no instruction to do so |
| prose answer, no narration | ✓ on benign questions |

The one thing it cannot fix from the client side is the header, because the server
overrides it. **Simpler header requires editing the server prompt.**

### One behavioural warning

With the "just do it, don't ask" rules, the model stopped refusing and started
acting — including on requests it had previously declined. On a benign question it
answers directly; on others it proceeds. That is the trade the prompt makes. If you
want a floor, add a line to the prompt yourself; I have not written one, because you
asked to remove constraints rather than add them.

---

## Still true from before

Your endpoint declares **no context length**, so opencode assumes 200,000 while the
model's real window is 32,768, and reserves 16,000 tokens — 49% — before a
conversation starts. `opencode.jsonc` in this folder fixes that with an explicit
`limit.context`. That is separate from the persona and still worth installing.
