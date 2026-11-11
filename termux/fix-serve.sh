#!/data/data/com.termux/files/usr/bin/bash
# Fix the "Starting background server... Server process exited with code 127" crash
# on an opencode that is ALREADY installed by termux/install.sh.
#
# Why it happens
# --------------
# The launcher ran the binary as:
#
#     ld-linux-aarch64.so.1 --library-path ... opencode.real
#
# Under that loader, process.execPath is the *loader*, not opencode. opencode
# restarts itself for its background server (`selfCommand()` -> `serve --service`),
# so it tried to execute:
#
#     ld-linux-aarch64.so.1 serve --service
#
# and the loader tried to load "serve" as a shared object:
#
#     serve: error while loading shared libraries: serve: cannot open shared object file
#
# The fix is to stop going through the loader by hand: point the binary's own
# ELF interpreter at Termux's glibc loader, so the kernel loads it directly and
# the binary can re-exec itself like any normal program.
set -euo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
GLIBC="$PREFIX/glibc/lib"
LD_SO="$GLIBC/ld-linux-aarch64.so.1"
REAL="$PREFIX/share/opencode/opencode.real"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[0;33m'; B='\033[0;34m'; N='\033[0m'
say()  { printf "%b==>%b %s\n" "$B" "$N" "$*"; }
ok()   { printf "%b ok%b %s\n" "$G" "$N" "$*"; }
warn() { printf "%b  !%b %s\n" "$Y" "$N" "$*"; }
die()  { printf "%b err%b %s\n" "$R" "$N" "$*" >&2; exit 1; }

command -v patchelf >/dev/null || die "patchelf missing — run: pkg install patchelf"
[ -f "$REAL" ] || die "no binary at $REAL — run termux/install.sh first"
[ -x "$LD_SO" ] || die "glibc runtime missing — run: pkg install glibc-repo && pkg install glibc glibc-runner"

# readelf -l reports the program-header *section name*, not the interpreter
# path, so grep the binary itself. This needs no extra packages.
if grep -aq "$LD_SO" "$REAL"; then
  ok "binary already points at the glibc loader"
else
  say "repointing the ELF interpreter at $LD_SO"
  patchelf --set-interpreter "$LD_SO" --set-rpath "$GLIBC" "$REAL"
  grep -aq "$LD_SO" "$REAL" || die "patchelf did not take — is the binary read-only?"
  ok "interpreter patched"
fi

say "rewriting the launcher to exec the binary directly"
cat > "$PREFIX/bin/opencode" <<'LAUNCHER'
#!/data/data/com.termux/files/usr/bin/bash
# opencode launcher for Termux.
# The binary's ELF interpreter is $PREFIX/glibc/lib/ld-linux-aarch64.so.1, so it
# runs on its own and can re-exec itself for its background server. Do not run
# it through the loader by hand — that makes process.execPath the loader and
# breaks `opencode serve`.
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
REAL="$PREFIX/share/opencode/opencode.real"

[ -x "$REAL" ] || { echo "opencode: binary missing at $REAL — re-run the installer" >&2; exit 1; }

# Android has no /tmp and Bun unpacks native modules somewhere writable.
export TMPDIR="${TMPDIR:-$PREFIX/tmp}"
mkdir -p "$TMPDIR"

# Termux exports a bionic LD_PRELOAD via libtermux-exec; the glibc loader rejects it.
export LD_PRELOAD=
unset LD_LIBRARY_PATH || true

exec "$REAL" "$@"
LAUNCHER
chmod 755 "$PREFIX/bin/opencode"
ok "$PREFIX/bin/opencode"

say "verifying"
V="$("$PREFIX/bin/opencode" --version 2>&1)" || { warn "version failed: $V"; exit 1; }
ok "opencode $V"

# The crash was in the background server, so prove that path works now.
say "checking the background server can spawn"
if OUT="$("$PREFIX/bin/opencode" serve --port 0 --stdio 2>&1 & sleep 4; kill %1 2>/dev/null)" && \
   ! printf '%s' "$OUT" | grep -q "cannot open shared object file"; then
  ok "server spawns (no loader error)"
else
  printf '%s\n' "$OUT" | sed 's/^/    /'
  die "server still failing — paste the above"
fi

echo
printf "%bFixed.%b  Run:  opencode\n" "$G" "$N"
