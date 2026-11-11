#!/data/data/com.termux/files/usr/bin/bash
# Install stock opencode (official aarch64 release) into Termux.
#
# No build, no fork. Downloads the official binary, wires up the glibc runtime
# Termux provides, and drops a launcher on PATH.
#
#   curl -fsSL <this-file> | bash
#
# Undo:  rm -f $PREFIX/bin/opencode && rm -rf $PREFIX/share/opencode
set -euo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
GLIBC="$PREFIX/glibc/lib"
BIN="$PREFIX/share/opencode/opencode.real"
URL="https://github.com/anomalyco/opencode/releases/latest/download/opencode-linux-arm64.tar.gz"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[0;33m'; B='\033[0;34m'; N='\033[0m'
say()  { printf "%b==>%b %s\n" "$B" "$N" "$*"; }
ok()   { printf "%b ok%b %s\n" "$G" "$N" "$*"; }
warn() { printf "%b  !%b %s\n" "$Y" "$N" "$*"; }
die()  { printf "%b err%b %s\n" "$R" "$N" "$*" >&2; exit 1; }

# ── 1. sanity ────────────────────────────────────────────────────────────────
[ -n "${TERMUX_VERSION:-}" ] || [ -d /data/data/com.termux ] || die "this is for Termux"
case "$(uname -m)" in
  aarch64|arm64) ;;
  *) die "needs aarch64; this device is $(uname -m)" ;;
esac
for b in curl tar; do command -v "$b" >/dev/null || die "missing $b — pkg install curl tar"; done
say "installing opencode (stock, official aarch64 build)"

# ── 2. glibc runtime ─────────────────────────────────────────────────────────
# opencode is a glibc binary; Android uses bionic. Termux supplies glibc.
say "checking glibc runtime"
if [ ! -x "$GLIBC/ld-linux-aarch64.so.1" ]; then
  warn "not present — installing (one-time, ~200 MB)"
  pkg install -y glibc-repo   >/dev/null 2>&1 || die "could not install glibc-repo"
  pkg update -y               >/dev/null 2>&1 || true
  pkg install -y glibc glibc-runner patchelf >/dev/null 2>&1 || die "could not install glibc"
fi
[ -x "$GLIBC/ld-linux-aarch64.so.1" ] || die "glibc loader still missing"
ok "glibc present"

# Android has no /etc/resolv.conf and Bun reads one for DNS.
if [ ! -f "$PREFIX/etc/resolv.conf" ]; then
  mkdir -p "$PREFIX/etc"
  printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > "$PREFIX/etc/resolv.conf"
  ok "wrote $PREFIX/etc/resolv.conf"
fi

# ── 3. download ──────────────────────────────────────────────────────────────
say "downloading (~78 MB)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl -fL --retry 3 --progress-bar -o "$TMP/oc.tar.gz" "$URL" || die "download failed"
tar -xzf "$TMP/oc.tar.gz" -C "$TMP"
[ -f "$TMP/opencode" ] || die "archive had no 'opencode' binary"
mkdir -p "$PREFIX/share/opencode"
install -m 755 "$TMP/opencode" "$BIN"
ok "binary installed ($(du -h "$BIN" | cut -f1))"

say "pointing the ELF interpreter at Termux's glibc loader"
command -v patchelf >/dev/null || die "patchelf missing — pkg install patchelf"
patchelf --set-interpreter "$GLIBC/ld-linux-aarch64.so.1" --set-rpath "$GLIBC" "$BIN"
grep -aq "$GLIBC/ld-linux-aarch64.so.1" "$BIN" || die "patchelf did not take"
ok "interpreter patched"

# ── 4. launcher ──────────────────────────────────────────────────────────────
say "writing launcher"
cat > "$PREFIX/bin/opencode" <<'LAUNCHER'
#!/data/data/com.termux/files/usr/bin/bash
# Runs the glibc-linked opencode through Termux's glibc loader.
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
GLIBC="$PREFIX/glibc/lib"
BIN="$PREFIX/share/opencode/opencode.real"

[ -x "$BIN" ] || { echo "opencode: missing $BIN — re-run the installer" >&2; exit 1; }
[ -x "$GLIBC/ld-linux-aarch64.so.1" ] || {
  echo "opencode: glibc runtime missing — pkg install glibc-repo && pkg install glibc glibc-runner" >&2
  exit 1
}

export TMPDIR="${TMPDIR:-$PREFIX/tmp}"   # Android has no /tmp
mkdir -p "$TMPDIR"

# Do NOT exec through the loader: process.execPath would become the loader and
# opencode could not re-exec itself (`serve`) for its background server.
export LD_PRELOAD=
unset LD_LIBRARY_PATH || true
exec "$BIN" "$@"
LAUNCHER
chmod 755 "$PREFIX/bin/opencode"
ok "$PREFIX/bin/opencode"

# ── 5. verify ────────────────────────────────────────────────────────────────
say "verifying"
if OUT="$("$PREFIX/bin/opencode" --version 2>&1)"; then
  ok "opencode $OUT"
else
  warn "did not report a version:"
  printf '%s\n' "$OUT" | sed 's/^/    /'
  cat <<'EOF'

  bad ELF magic            -> run: unset LD_LIBRARY_PATH
  required file not found  -> pkg install glibc glibc-runner
  Bad system call          -> old Android; pkg install glibc-runner then reboot
EOF
  exit 1
fi

echo
printf "%bDone.%b  Run it:  opencode\n" "$G" "$N"
echo
echo "  Next: run the wrapper to point it at your endpoint:"
echo "    opencode-custom"
echo
