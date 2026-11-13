#!/bin/sh
# Fix: "serve: error while loading shared libraries: serve"
# The launcher must exec the binary directly, not through the glibc loader.
set -e
L="$PREFIX/bin/opencode"
OPT="$PREFIX/opt/opencode"
GLIBC="$PREFIX/glibc/lib"

if [ ! -f "$OPT/opencode" ]; then
  echo "!! $OPT/opencode missing - run install-oc3.sh first"; exit 1
fi

# make sure PT_INTERP points at Termux glibc (install-oc3.sh does this too)
if command -v patchelf >/dev/null 2>&1; then
  patchelf --set-interpreter "$GLIBC/ld-linux-aarch64.so.1" "$OPT/opencode" 2>/dev/null \
    && echo "  interpreter re-patched"
fi

cat > "$L" <<'SH'
#!/data/data/com.termux/files/usr/bin/sh
GLIBC="$PREFIX/glibc/lib"
OPT="$PREFIX/opt/opencode"
BIN="$OPT/opencode"
if [ ! -x "$GLIBC/ld-linux-aarch64.so.1" ]; then
  echo "opencode: glibc missing - pkg install glibc-repo && pkg install glibc glibc-runner" >&2
  exit 1
fi
[ -f "$BIN" ] || { echo "opencode: $BIN missing - re-run install-oc3.sh" >&2; exit 1; }
# Direct exec: PT_INTERP already points at Termux glibc, so the kernel loads
# it. Running it through ld-linux breaks opencode's background server, which
# re-execs process.execPath as `serve`.
exec env -u LD_PRELOAD LD_LIBRARY_PATH="$GLIBC:$OPT" "$BIN" "$@"
SH
chmod +x "$L"
echo "launcher rewritten (direct exec, LD_PRELOAD scrubbed)"

echo
echo "testing:"
if OUT=$(opencode --version 2>&1); then echo "  ok $OUT"; else
  echo "  version failed:"; echo "$OUT" | head -3 | sed 's/^/    /'; exit 1
fi

echo "  starting server as a smoke test"
opencode serve --port 4596 --hostname 127.0.0.1 >"$HOME/.cache/oc-serve.log" 2>&1 &
SP=$!
sleep 10
if curl -sS -m 4 -o /dev/null http://127.0.0.1:4596/ 2>/dev/null; then
  echo "  ok background server responds"
  kill $SP 2>/dev/null
  echo
  echo "================ READY ================"
  echo "  run:  opencode --continue"
  echo "======================================="
else
  echo "  server did not respond; log:"
  head -8 "$HOME/.cache/oc-serve.log" 2>/dev/null | sed 's/^/    /'
  kill $SP 2>/dev/null
fi
