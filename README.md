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

## The build is already done

The patched binary is built and attached to a release — you do not need to run
CI, tag anything, or push anything.

<https://github.com/AmbitiousBoyII14/opencode-termux/releases/tag/v1.0.1>

| | |
|---|---|
| file | `opencode-termux-aarch64.tar.gz` |
| size | 91 MB compressed, 218 MB unpacked |
| sha256 | see `SHA256SUMS` in the same release |
| built from | upstream `144438a` + `patch/opencode-custom-connect.patch` |
| verified | `Machine: AArch64`, custom-endpoint strings present, ELF interpreter pre-pointed at Termux's glibc loader |

To install it, jump to step 4 below.

---

## Installing the patched build

```bash
pkg install -y glibc-repo && pkg update && pkg install -y glibc glibc-runner
curl -fsSL https://raw.githubusercontent.com/AmbitiousBoyII14/opencode-termux/main/termux/install.sh | bash
opencode
```

Now `/connect` opens the custom-endpoint form instead of the provider catalogue.

### Rebuilding it yourself (optional)

Only useful if you want to change the patch. Pushing a `v*` tag triggers the
workflow and attaches a fresh release; you can also run it from the Actions tab
with a custom `upstream_ref`.

```bash
export GITHUB_TOKEN=ghp_…
cd oc-termux-repo
./push.sh YOUR_USERNAME opencode-termux     # only if you forked it
git tag v1.0.1 && git push origin v1.0.1    # build + attach to a release
```

---

## Which am I on?

```bash
opencode --version     # works?
opencode-custom show   # which endpoint is it pointing at?
```

| you installed | `opencode` | `/connect` inside the app |
|---|---|---|
| stock (steps 1–3) | works | provider catalogue |
| patched (release above) | works | custom form |

---

## When something breaks

| what you see | what it means | fix |
|---|---|---|
| `bad ELF magic` from `cat` or `ls` | `LD_LIBRARY_PATH` leaked into your shell | `unset LD_LIBRARY_PATH` |
| `cannot execute: required file not found` | glibc runtime missing | `pkg install glibc-repo && pkg install glibc glibc-runner` |
| `Bad system call` | Android 10/11 blocking a syscall | `pkg install glibc-runner`, then reboot |
| API calls all fail | no `resolv.conf` | re-run `install-opencode.sh` |
| `Unsupported package for custom/…:` | config is in the old v1 shape | delete `~/.config/opencode/opencode.jsonc` and run `opencode-custom` again |
| `Server process exited with code 127` / `serve: cannot open shared object file` | binary was run through the loader, so it cannot re-exec itself | `pkg install patchelf` then run `termux/fix-serve.sh`, or install v1.0.1+ |
| `jq: not found` | missing | `pkg install jq` |
| right username missing in URLs | `AmbitiousBoyII14/opencode-termux` wasn't stamped | run `./push.sh` on your computer, or edit the URLs by hand |

---

## The `serve` exit-127 bug (fixed in v1.0.1)

If you installed v1.0.0 you saw this on every launch:

```
Starting background server...
Error: Server process exited with code 127
serve: error while loading shared libraries: serve: cannot open shared object file
```

**Cause.** The launcher ran the binary by hand through the loader:

```bash
ld-linux-aarch64.so.1 --library-path ... opencode.real
```

Under that, `process.execPath` is the **loader**, not opencode. opencode re-execs
itself to start its background server (`selfCommand()` → `serve --service`), so it
ran `ld-linux-aarch64.so.1 serve --service` — and the loader tried to open `serve`
as a shared library. Exit 127.

**Fix.** Don't invoke the loader manually. Point the binary's own ELF interpreter
at the loader and let the kernel do it:

```bash
patchelf --set-interpreter "$PREFIX/glibc/lib/ld-linux-aarch64.so.1" \
         --set-rpath "$PREFIX/glibc/lib" \
         "$PREFIX/share/opencode/opencode.real"
```

Now `process.execPath` is the binary, and `exec` of `serve` works normally.

**Already installed?** Don't re-download 91 MB — patch in place:

```bash
pkg install patchelf
curl -fsSL https://raw.githubusercontent.com/AmbitiousBoyII14/opencode-termux/main/termux/fix-serve.sh | bash
```

The CI build now bakes this in, so v1.0.1+ needs no `patchelf` on the device.

## What's in here

```
termux/install-opencode.sh   installs stock opencode for Termux   <- step 2
termux/opencode-custom       endpoint wrapper                     <- step 3
termux/install.sh            installs the PATCHED build           <- step 4
termux/fix-serve.sh          repairs an existing v1.0.0 install
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
