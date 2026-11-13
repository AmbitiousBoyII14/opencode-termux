#!/bin/sh
# Fix: "libc.so: invalid ELF header" when running opencode on Termux.
# Bun dlopen()s "libc.so"; Termux ships it as a text linker script.
GLIBC="$PREFIX/glibc/lib"

if [ ! -d "$GLIBC" ]; then
  echo "!! $GLIBC missing - pkg install glibc-repo && pkg install glibc glibc-runner"
  exit 1
fi

echo "current:"
ls -la "$GLIBC/libc.so" "$GLIBC/libc.so.6" 2>/dev/null | awk '{print "  "$5" "$9" "$10" "$11}'

if [ -f "$GLIBC/libc.so" ] && ! head -c 4 "$GLIBC/libc.so" 2>/dev/null | grep -q ELF; then
  echo "libc.so is a linker script -> replacing with a link to libc.so.6"
  mv -f "$GLIBC/libc.so" "$GLIBC/libc.so.script" 2>/dev/null || true
  ln -sf libc.so.6 "$GLIBC/libc.so"
  echo "  done"
else
  echo "libc.so is already a real ELF - nothing to fix"
fi

echo
echo "testing:"
if command -v opencode >/dev/null 2>&1; then
  OUT=$(opencode --version 2>&1) && echo "  ok opencode $OUT" || { echo "  still failing:"; echo "$OUT" | head -4 | sed 's/^/    /'; }
fi
