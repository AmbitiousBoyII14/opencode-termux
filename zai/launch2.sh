#!/data/data/com.termux/files/usr/bin/sh
# opencode launcher for Termux - v2.
#
# v1 exec'd the glibc loader:
#     exec ld-linux --library-path ... $OPT/opencode "$@"
# That breaks opencode's own background server. opencode re-execs itself as
# `serve`; with the loader as process.execPath it spawns
#     ld-linux serve
# which the loader reads as "load the program named serve":
#     serve: error while loading shared libraries: serve: cannot open ...
# (reproduced exactly on x86: `ld-linux serve` -> same message)
#
# So: exec the BINARY DIRECTLY. install-oc3.sh already patched its PT_INTERP
# to point at $PREFIX/glibc/lib/ld-linux-aarch64.so.1, so the kernel invokes
# the right loader automatically - and process.execPath is the real binary,
# which is what the background server needs.
#
# Only LD_PRELOAD is scrubbed: termux-exec's preload is a bionic library and
# glibc rejects it with "version `LIBC' not found".
GLIBC="$PREFIX/glibc/lib"
OPT="$PREFIX/opt/opencode"
BIN="$OPT/opencode"

if [ ! -x "$GLIBC/ld-linux-aarch64.so.1" ]; then
  echo "opencode: glibc runtime missing" >&2
  echo "  pkg install glibc-repo && pkg install glibc glibc-runner" >&2
  exit 1
fi
if [ ! -f "$BIN" ]; then
  echo "opencode: binary missing at $BIN - re-run install-oc3.sh" >&2
  exit 1
fi
if ! head -c 4 "$BIN" | grep -q ELF; then
  echo "opencode: $BIN is not an ELF binary" >&2
  exit 1
fi

# LD_LIBRARY_PATH is kept: the binary's own libs live in $OPT
exec env -u LD_PRELOAD LD_LIBRARY_PATH="$GLIBC:$OPT" "$BIN" "$@"
