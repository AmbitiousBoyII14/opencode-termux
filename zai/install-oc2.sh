#!/bin/sh
# Install opencode 2.3.0 (the 2.x line) on Termux/aarch64.
# The 1.x line CANNOT read a session_v2 database - that is what causes
# "Database is not empty and has no session table".
set -e
VERSION="v2.3.0"
URL="https://github.com/anomalyco/opencode/releases/download/$VERSION/opencode-linux-arm64.tar.gz"
GLIBC="$PREFIX/glibc/lib"
OPT="$PREFIX/opt/opencode"

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
ok()  { printf ' \033[32mok\033[0m %s\n' "$*"; }
die() { printf '\033[31m!!\033[0m %s\n' "$*" >&2; exit 1; }

for b in curl tar; do command -v "$b" >/dev/null || die "missing $b - pkg install curl tar"; done

say "glibc runtime"
if [ ! -x "$GLIBC/ld-linux-aarch64.so.1" ]; then
  pkg install -y glibc-repo >/dev/null 2>&1 || die "could not install glibc-repo"
  pkg install -y glibc glibc-runner patchelf >/dev/null 2>&1 || die "could not install glibc"
fi
[ -x "$GLIBC/ld-linux-aarch64.so.1" ] || die "glibc loader still missing"
command -v patchelf >/dev/null || pkg install -y patchelf >/dev/null 2>&1
ok "glibc present"

say "downloading opencode $VERSION (~115 MB)"
mkdir -p "$HOME/.cache"
TAR="$HOME/.cache/oc-$VERSION.tar.gz"
curl -fL --retry 3 --progress-bar -o "$TAR" "$URL" || die "download failed"
ok "downloaded ($(du -h "$TAR" | cut -f1))"

say "extracting"
rm -rf "$OPT"; mkdir -p "$OPT"
tar -xzf "$TAR" -C "$OPT"
BIN="$OPT/opencode"
[ -f "$BIN" ] || BIN=$(find "$OPT" -maxdepth 2 -type f -name opencode | head -1)
[ -n "$BIN" ] && [ -f "$BIN" ] || die "binary not found in archive"
chmod +x "$BIN"
ok "binary installed ($(du -h "$BIN" | cut -f1))"

say "pointing the ELF interpreter at Termux's glibc loader"
patchelf --set-interpreter "$GLIBC/ld-linux-aarch64.so.1" "$BIN" || die "patchelf failed"
ok "interpreter patched"

say "fixing Termux's libc.so linker-script trap"
# Bun dlopen()s "libc.so" at startup. Termux ships glibc's libc.so as a TEXT
# linker script (GROUP ( libc.so.6 )), so dlopen fails with
#   "libc.so: invalid ELF header"
# Point libc.so at the real shared object instead.
if [ -f "$GLIBC/libc.so" ] && ! head -c 4 "$GLIBC/libc.so" 2>/dev/null | grep -q ELF; then
  cp -f "$GLIBC/libc.so" "$GLIBC/libc.so.script" 2>/dev/null || true
  ln -sf libc.so.6 "$GLIBC/libc.so"
  ok "libc.so -> libc.so.6 (was a linker script)"
else
  ok "libc.so already a real ELF"
fi

say "writing launcher"
cat > "$PREFIX/bin/opencode" <<'LAUNCH'
#!/data/data/com.termux/files/usr/bin/sh
GLIBC="$PREFIX/glibc/lib"
OPT="$PREFIX/opt/opencode"
if [ ! -x "$GLIBC/ld-linux-aarch64.so.1" ]; then
  echo "opencode: glibc missing - pkg install glibc-repo && pkg install glibc glibc-runner" >&2
  exit 1
fi
exec "$GLIBC/ld-linux-aarch64.so.1" --library-path "$GLIBC:$OPT" "$OPT/opencode" "$@"
LAUNCH
chmod +x "$PREFIX/bin/opencode"
ok "$PREFIX/bin/opencode"

say "verifying"
if OUT=$(opencode --version 2>&1); then
  ok "opencode $OUT"
else
  echo "$OUT" | head -20
  die "did not report a version"
fi

rm -f "$TAR"
echo
echo "Done. 2.x line installed - this one understands session_v2."
echo "  run:  opencode --continue"
