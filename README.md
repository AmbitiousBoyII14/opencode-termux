# opencode on Termux — step by step

Two commands on your phone. That's it.

---

## On your phone (Termux)

### 1. Install dependencies

```bash
pkg update && pkg upgrade -y
pkg install -y curl tar jq glibc-repo
pkg update -y
pkg install -y glibc glibc-runner
```

`glibc` is the important one: opencode is a glibc binary and Android uses bionic,
so Termux has to provide a glibc for it to run against. This is a one-time ~200 MB
download.

### 2. Install opencode

```bash
curl -fsSL https://raw.githubusercontent.com/AmbitiousBoyII14/opencode-termux/main/termux/install-opencode.sh | bash
```

That downloads the **official** opencode aarch64 binary, installs it, writes a
launcher that runs it through Termux's glibc loader, and checks it reports a
version. If the last line is `opencode v2.x.x` you're done with this step.

### 3. Point it at your endpoint

```bash
curl -fsSL https://raw.githubusercontent.com/AmbitiousBoyII14/opencode-termux/main/termux/opencode-custom \
  -o $PREFIX/bin/opencode-custom
chmod +x $PREFIX/bin/opencode-custom
opencode-custom
```

It asks three things and then launches opencode:

```
  ▌ Connect a custom endpoint
  Any OpenAI-compatible API. Nothing else to choose.

  base URL [https://host/v1]: https://your-host/v1
  api key (blank keeps the current one):
  model ID [glm-4.7-flash]: glm-4.7-flash

 ✓ saved
    endpoint  https://your-host/v1
    model     glm-4.7-flash
```

Next time just run `opencode-custom`. It remembers, and it will ask before
changing anything.

---

## On your computer (only if you want `/connect` itself changed)

Everything above gives you opencode on Termux pointed at your endpoint. The only
thing it does **not** do is change what happens when you type `/connect` *inside*
the app — that still shows the provider catalogue.

To change that too, you need the patched build. This is optional.

### 1. Push this repo

You need a GitHub token with `repo` and `workflow` scopes:
<https://github.com/settings/tokens>

```bash
export GITHUB_TOKEN=ghp_yourtoken
cd oc-termux-repo
./push.sh YOUR_GITHUB_USERNAME opencode-termux
```

Wait for it to print `pushed: https://github.com/YOUR_USERNAME/opencode-termux`.
The script stamps your username into the installer paths, so step 2 on your phone
will point at your repo.

### 2. Run the build

On github.com, open your new repo → **Actions** → **build-termux** → **Run
workflow** → **Run workflow**.

Takes about 15 minutes. Cross-compiles aarch64 on an x64 runner, which is the only
place it can be built — it needs more than 2 GB RAM.

### 3. Tag a release

When the run is green, back in **Actions** the artifact exists but isn't
downloadable by a URL yet. Tag it:

```bash
cd oc-termux-repo
git tag v1.0.0
git push origin v1.0.0
```

That triggers another run and attaches `opencode-termux-aarch64.tar.gz` to a
Release. Now `termux/install.sh` has something to download.

### 4. Install the patched one on your phone

```bash
pkg install -y glibc-repo && pkg update && pkg install -y glibc glibc-runner
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/opencode-termux/main/termux/install.sh | bash
opencode
```

Now `/connect` opens the custom-endpoint form.

---

## Which am I on?

```bash
opencode --version     # works?
opencode-custom show   # which endpoint is it pointing at?
```

| you have | `opencode` | `/connect` inside the app |
|---|---|---|
| steps 1–3 above | works | provider catalogue |
| + the optional build | works | custom form |

---

## When something breaks

| what you see | what it means | fix |
|---|---|---|
| `bad ELF magic` from `cat` or `ls` | `LD_LIBRARY_PATH` leaked into your shell | `unset LD_LIBRARY_PATH` |
| `cannot execute: required file not found` | glibc runtime missing | `pkg install glibc-repo && pkg install glibc glibc-runner` |
| `Bad system call` | Android 10/11 blocking a syscall | `pkg install glibc-runner`, then reboot |
| API calls all fail | no `resolv.conf` | re-run `install-opencode.sh` |
| `Unsupported package for custom/…:` | config is in the old v1 shape | delete `~/.config/opencode/opencode.jsonc` and run `opencode-custom` again |
| `jq: not found` | missing | `pkg install jq` |
| right username missing in URLs | `AmbitiousBoyII14/opencode-termux` wasn't stamped | run `./push.sh` on your computer, or edit the URLs by hand |

---

## What's in here

```
termux/install-opencode.sh   installs stock opencode for Termux   <- step 2
termux/opencode-custom       endpoint wrapper                     <- step 3
termux/install.sh            installs the PATCHED build           <- optional step 4
patch/opencode-custom-connect.patch   the only source change
.github/workflows/build-termux.yml    the CI build
push.sh                      creates the repo and pushes
wrapper/README.md            notes on the wrapper
```

---

## Why the wrapper rather than just editing config by hand

You can do it by hand — it's just this file, `~/.config/opencode/opencode.jsonc`:

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

Two things trip people up, which is why the wrapper exists:

- it must be `providers` (plural) with `package` + `settings` — the older
  `npm` + `options` form is silently dropped and you get
  `Unsupported package for custom/…:` with nothing after the colon
- every model needs its own `package` too

The wrapper writes that shape correctly and is idempotent, so re-running it just
updates the endpoint instead of duplicating entries.
