#!/bin/sh
# Fix: "version `LIBC' not found (required by libtermux-exec-ld-preload.so)"
# Rewrites ONLY the opencode launcher to scrub LD_PRELOAD. Nothing else touched.
set -e
LAUNCHER="$PREFIX/bin/opencode"

echo "before:"; ls -la "$LAUNCHER" 2>/dev/null | awk '{print "  "$5" bytes"}'
head -3 "$LAUNCHER" 2>/dev/null | sed 's/^/  | /'

cat > "$LAUNCHER" <<'SH'
#!/data/data/com.termux/files/usr/bin/sh
GLIBC="$PREFIX/glibc/lib"
OPT="$PREFIX/opt/opencode"
if [ ! -x "$GLIBC/ld-linux-aarch64.so.1" ]; then
  echo "opencode: glibc missing - pkg install glibc-repo && pkg install glibc glibc-runner" >&2
  exit 1
fi
# termux-exec's LD_PRELOAD is a bionic lib; glibc rejects it with
# "version \`LIBC' not found". Scrub it before exec.
exec env -u LD_PRELOAD -u LD_LIBRARY_PATH \
  "$GLIBC/ld-linux-aarch64.so.1" --library-path "$GLIBC:$OPT" "$OPT/opencode" "$@"
SH
chmod +x "$LAUNCHER"
echo "after:"; head -2 "$LAUNCHER" | sed 's/^/  | /'

echo
echo "testing:"
if OUT=$(opencode --version 2>&1); then
  echo "  ok opencode $OUT"
else
  echo "  still failing:"; echo "$OUT" | head -4 | sed 's/^/    /'
  echo
  echo "  next diagnostic:"
  echo "    echo \$LD_PRELOAD"
  echo "    ls -la \$PREFIX/glibc/lib/libc.so"
fi
