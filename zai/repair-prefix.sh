#!/bin/sh
# Repair whatever libc.so/libm.so damage exists in $PREFIX after the
# LD_LIBRARY_PATH leak, then verify core tools link again.
echo "==> state of $PREFIX/glibc/lib"
ls -la "$PREFIX/glibc/lib/libc.so" "$PREFIX/glibc/lib/libm.so" 2>/dev/null | sed 's/^/   /'

echo "==> reinstall the glibc + core packages"
pkg update -y >/dev/null 2>&1
pkg install -y glibc glibc-runner >/dev/null 2>&1 && echo "   glibc ok"
pkg reinstall -y coreutils bash 2>/dev/null || pkg install -y bash

echo
echo "==> verifying shells link"
for b in bash sh ls; do
  if out=$("$b" -c 'echo ok' 2>&1); then
    echo "   $b: $out"
  else
    echo "   $b: FAILED -> $out"
  fi
done
