#!/bin/sh
# v5: bake RUNPATH via copy + atomic swap.
#
# v4 called patchelf on the live binary:
#     patchelf: open: Text file busy        (ETXTBSY - it is running)
# v5 never writes to a file that is executing.
set -e
GLIBC="$PREFIX/glibc/lib"
OPT="$PREFIX/opt/opencode"
BIN="$OPT/opencode"
L="$PREFIX/bin/opencode"
NEW="$OPT/.opencode.new"

[ -f "$BIN" ] || { echo "!! $BIN missing - run install-oc4.sh"; exit 1; }
command -v patchelf >/dev/null || pkg install -y patchelf >/dev/null 2>&1

echo "==> stopping any running opencode (needed before touching the binary)"
pkill -f 'opencode serve' 2>/dev/null || true
pkill -f "$OPT/opencode" 2>/dev/null || true
sleep 2

echo "==> building a patched copy"
rm -f "$NEW"
cp "$BIN" "$NEW"
patchelf --set-rpath "$OPT:$GLIBC" "$NEW"
patchelf --set-interpreter "$GLIBC/ld-linux-aarch64.so.1" "$NEW"
chmod +x "$NEW"
echo "   RUNPATH: $(readelf -d "$NEW" 2>/dev/null | sed -n 's/.*RUNPATH.*\[\(.*\)\]/\1/p' | head -1)"

echo "==> atomic swap"
mv -f "$NEW" "$BIN"
echo "   swapped"

echo "==> rewriting launcher (exports nothing)"
cat > "$L" <<'SH'
#!/data/data/com.termux/files/usr/bin/sh
GLIBC="$PREFIX/glibc/lib"
OPT="$PREFIX/opt/opencode"
BIN="$OPT/opencode"
if [ ! -x "$GLIBC/ld-linux-aarch64.so.1" ]; then
  echo "opencode: glibc missing - pkg install glibc-repo && pkg install glibc glibc-runner" >&2
  exit 1
fi
[ -f "$BIN" ] || { echo "opencode: $BIN missing" >&2; exit 1; }
# No LD_LIBRARY_PATH: children (bash, ls, pkg) are bionic and would load glibc
# libs and fail. RUNPATH inside the binary covers opencode's own libs.
exec env -u LD_PRELOAD -u LD_LIBRARY_PATH "$BIN" "$@"
SH
chmod +x "$L"

echo
echo "==> verifying"
if OUT=$(opencode --version 2>&1); then echo "   opencode: $OUT"; else
  echo "   FAILED:"; echo "$OUT" | head -3 | sed 's/^/     /'; exit 1; fi

# correct tool checks: run each with -c/--version, never `ls -c`
for t in bash sh; do
  if OUT=$("$t" -c 'echo ok' 2>&1); then echo "   $t: ok"; else echo "   $t BROKEN: $OUT"; fi
done
if ls -d "$HOME" >/dev/null 2>&1; then echo "   ls: ok"; else echo "   ls BROKEN"; fi

echo
echo "==> child-shell test through opencode's environment"
env -u LD_PRELOAD -u LD_LIBRARY_PATH sh -c 'echo "   child sh: ok"' 2>&1 | tail -1
