#!/data/data/com.termux/files/usr/bin/sh
# opencode launcher, v3.
#
# v2 set LD_LIBRARY_PATH="$GLIBC:$OPT". opencode passes its environment to every
# child process, so Termux's BIONIC binaries (bash, ls, unzip, pkg...) searched
# the glibc directory first and died with:
#     CANNOT LINK EXECUTABLE .../bash: cannot find "libc.so" from verneed[1]
# i.e. the agent's shell stopped working entirely.
#
# v3 exports NOTHING. The library path is baked into the binary as RUNPATH by
# install-oc4.sh / relink4.sh, so the loader finds it without polluting the
# environment of child processes.
GLIBC="$PREFIX/glibc/lib"
OPT="$PREFIX/opt/opencode"
BIN="$OPT/opencode"

if [ ! -x "$GLIBC/ld-linux-aarch64.so.1" ]; then
  echo "opencode: glibc runtime missing" >&2
  echo "  pkg install glibc-repo && pkg install glibc glibc-runner" >&2
  exit 1
fi
[ -f "$BIN" ] || { echo "opencode: $BIN missing - re-run install-oc4.sh" >&2; exit 1; }

# Scrub only what breaks glibc binaries. Deliberately do NOT set
# LD_LIBRARY_PATH - the RUNPATH inside the binary handles that.
exec env -u LD_PRELOAD -u LD_LIBRARY_PATH "$BIN" "$@"
