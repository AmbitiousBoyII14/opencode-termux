# The wrapper (no build, no fork)

Use this if you don't want to wait for a build. It works with **stock opencode** —
the one you can install in Termux already.

```bash
opencode-custom                 # asks for URL, key, model — then launches opencode
opencode-custom set <url> <key> <model>
opencode-custom model <id>
opencode-custom show
```

It writes exactly what the patched `/connect` dialog writes:

```jsonc
{
  "providers": {
    "custom": {
      "name": "Custom",
      "package": "@opencode/ai/providers/openai-compatible",
      "settings": { "baseURL": "https://host/v1", "apiKey": "sk-…" },
      "models": {
        "glm-4.7-flash": {
          "name": "glm-4.7-flash",
          "package": "@opencode/ai/providers/openai-compatible"
        }
      }
    }
  },
  "model": { "providerID": "custom", "model": "glm-4.7-flash" }
}
```

then launches `opencode --model custom/<id>`.

## Verified

Against **unpatched** upstream source (patch removed entirely):

```
$ bun run src/index.ts run "Reply with exactly: stock plus wrapper works"
> build · glm-4.7-flash
stock plus wrapper works
```

## Difference from the fork

| | wrapper | patched fork |
|---|---|---|
| needs a build | no | yes (CI, ~15 min) |
| needs a fork repo | no | yes |
| `opencode` alone | normal provider catalogue | custom form |
| `/connect` in TUI | unchanged | custom form |
| switching endpoint | `opencode-custom` | `/connect` |

The wrapper only changes how you get *into* a session. If you type `/connect`
inside opencode you still get the catalogue — that is the one thing only the
fork fixes.
