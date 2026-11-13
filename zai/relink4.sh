#!/bin/sh
# Fix the "child shell cannot link bash" breakage.
# Bakes the glibc lib path into opencode as RUNPATH and stops exporting
# LD_LIBRARY_PATH to children.
set -e
GLIBC="$PREFIX/glibc/lib"
OPT="$PREFIX/opt/opencode"
BIN="$OPT/opencode"
L="$PREFIX/bin/opencode"

[ -f "$BIN" ] || { echo "!! $BIN missing - run install-oc4.sh"; exit 1; }
command -v patchelf >/dev/null || pkg install -y patchelf >/dev/null 2>&1

echo "==> baking RUNPATH into the binary (no env needed)"
patchelf --set-rpath "$OPT:$GLIBC" "$BIN"
patchelf --set-interpreter "$GLIBC/ld-linux-aarch64.so.1" "$BIN"
readelf -d "$BIN" 2>/dev/null | grep -i runpath | sed 's/^/   /'

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
[ -f "$BIN" ] || { echo "opencode: $BIN missing - re-run install-oc4.sh" >&2; exit 1; }
# Do NOT export LD_LIBRARY_PATH: children (bash, ls, pkg) are bionic and would
# pick up glibc libs and fail with "cannot find libc.so". RUNPATH covers us.
exec env -u LD_PRELOAD -u LD_LIBRARY_PATH "$BIN" "$@"
SH
chmod +x "$L"

echo
echo "==> verifying"
if OUT=$(opencode --version 2>&1); then echo "   ok $OUT"; else
  echo "   FAILED:"; echo "$OUT" | head -3 | sed 's/^/     /'; exit 1; fi

echo "==> verifying a child shell still works"
if OUT=$(sh -c 'echo child-ok' 2>&1); then echo "   sh: $OUT"; else
  echo "   sh BROKEN: $OUT"; echo "   -> run repair-prefix.sh"; fi
