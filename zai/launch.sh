#!/data/data/com.termux/files/usr/bin/sh
# opencode launcher for Termux.
#
# Two Android/Termux traps handled here:
#
# 1. termux-exec injects LD_PRELOAD=$PREFIX/lib/libtermux-exec-ld-preload.so
#    into every process. It is a BIONIC library and needs a symbol version
#    called LIBC that glibc does not have. Running a glibc binary with it
#    gives:
#       version `LIBC' not found (required by libtermux-exec-ld-preload.so)
#    Clearing LD_PRELOAD before exec fixes it. Nothing is lost: the exec it
#    wraps is being done here, explicitly.
#
# 2. Termux ships glibc's libc.so as a TEXT linker script. Bun dlopen()s
#    libc.so and fails with "invalid ELF header". install-oc3.sh repoints
#    libc.so at libc.so.6.
GLIBC="$PREFIX/glibc/lib"
OPT="$PREFIX/opt/opencode"
BIN="$OPT/opencode"

if [ ! -x "$GLIBC/ld-linux-aarch64.so.1" ]; then
  echo "opencode: glibc runtime missing" >&2
  echo "  pkg install glibc-repo && pkg install glibc glibc-runner" >&2
  exit 1
fi
if [ ! -f "$BIN" ]; then
  echo "opencode: binary missing at $BIN" >&2
  echo "  re-run install-oc3.sh" >&2
  exit 1
fi

exec env -u LD_PRELOAD -u LD_LIBRARY_PATH \
  "$GLIBC/ld-linux-aarch64.so.1" --library-path "$GLIBC:$OPT" "$BIN" "$@"
