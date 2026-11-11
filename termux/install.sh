#!/data/data/com.termux/files/usr/bin/bash
# opencode for Termux (aarch64) — installer
#
# Installs a patched opencode (custom-only /connect) alongside the glibc runtime it needs.
# Everything lives under $PREFIX; nothing touches system files, no root, no proot.
#
#   curl -fsSL https://raw.githubusercontent.com/<you>/<repo>/main/termux/install.sh | bash
#
set -euo pipefail

REPO="${OPENCODE_TERMUX_REPO:-AmbitiousBoyII14/opencode-termux}"
VERSION="${VERSION:-latest}"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[0;33m'; B='\033[0;34m'; N='\033[0m'
say()  { printf "%b==>%b %s\n" "$B" "$N" "$*"; }
ok()   { printf "%b  ok%b %s\n" "$G" "$N" "$*"; }
warn() { printf "%b  !!%b %s\n" "$Y" "$N" "$*"; }
die()  { printf "%b error%b %s\n" "$R" "$N" "$*" >&2; exit 1; }

# ── preflight ────────────────────────────────────────────────────────────────
[ -n "${TERMUX_VERSION:-}" ] || [ -d /data/data/com.termux ] || die "this installer is for Termux"
case "$(uname -m)" in
  aarch64|arm64) ;;
  *) die "needs aarch64/arm64; this device reports $(uname -m). 32-bit ARM and x86 are not built." ;;
esac

for bin in curl tar; do
  command -v "$bin" >/dev/null 2>&1 || die "missing '$bin' — run: pkg install curl tar"
done

say "installing opencode for Termux (aarch64)"

# ── glibc runtime ────────────────────────────────────────────────────────────
# opencode is a glibc-linked Bun binary. Android has no glibc, so Termux supplies one.
say "checking the glibc runtime"
if [ ! -x "$PREFIX/glibc/lib/ld-linux-aarch64.so.1" ]; then
  warn "glibc not found — installing (this is a one-time ~200 MB download)"
  pkg install -y glibc-repo >/dev/null 2>&1 || die "could not install glibc-repo"
  pkg update -y >/dev/null 2>&1 || true
  pkg install -y glibc glibc-runner >/dev/null 2>&1 || die "could not install glibc / glibc-runner"
fi
[ -x "$PREFIX/glibc/lib/ld-linux-aarch64.so.1" ] || die "glibc loader still missing after install"
ok "glibc runtime present"

# Android has no /etc/resolv.conf; Bun reads it for DNS and would fail on every API call.
if [ ! -f "$PREFIX/etc/resolv.conf" ]; then
  say "writing $PREFIX/etc/resolv.conf"
  mkdir -p "$PREFIX/etc"
  printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > "$PREFIX/etc/resolv.conf"
fi

# ── payload ──────────────────────────────────────────────────────────────────
say "downloading the binary"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ "$VERSION" = "latest" ]; then
  URL="https://github.com/${REPO}/releases/latest/download/opencode-termux-aarch64.tar.gz"
else
  URL="https://github.com/${REPO}/releases/download/${VERSION}/opencode-termux-aarch64.tar.gz"
fi

curl -fL --retry 3 --progress-bar -o "$TMP/oc.tar.gz" "$URL" \
  || die "download failed — is there a release at ${REPO}?"

# checksum, when the release publishes one
if curl -fsL --retry 2 -o "$TMP/SHA256SUMS" \
     "$(dirname "$URL")/SHA256SUMS" 2>/dev/null; then
  EXPECTED="$(awk '/opencode-termux-aarch64.tar.gz/{print $1}' "$TMP/SHA256SUMS" | head -1)"
  if [ -n "$EXPECTED" ]; then
    ACTUAL="$(sha256sum "$TMP/oc.tar.gz" | awk '{print $1}')"
    [ "$EXPECTED" = "$ACTUAL" ] || die "checksum mismatch (expected $EXPECTED, got $ACTUAL)"
    ok "checksum verified"
  fi
fi

tar -xzf "$TMP/oc.tar.gz" -C "$TMP"
[ -f "$TMP/opencode" ] || die "archive did not contain an 'opencode' binary"

mkdir -p "$PREFIX/share/opencode"
install -m 755 "$TMP/opencode" "$PREFIX/share/opencode/opencode.real"
ok "installed binary ($(du -h "$PREFIX/share/opencode/opencode.real" | cut -f1))"

# Point the binary's own ELF interpreter at Termux's glibc loader. Running it as
# `ld-linux ... binary` instead would make process.execPath the loader, which
# breaks opencode's self-respawn for its background server (`serve`).
say "pointing the ELF interpreter at Termux's glibc loader"
if command -v patchelf >/dev/null; then
  patchelf --set-interpreter "$GLIBC/ld-linux-aarch64.so.1" \
           --set-rpath "$GLIBC" \
           "$PREFIX/share/opencode/opencode.real"
  # readelf -l shows the section name, not the path, so grep the binary.
  grep -aq "$GLIBC/ld-linux-aarch64.so.1" "$PREFIX/share/opencode/opencode.real" \
    || die "patchelf did not take — the background server will not start"
  ok "interpreter patched"
else
  warn "patchelf missing — background server will not start"
  warn "run: pkg install patchelf && then re-run this installer"
fi

# ── launcher ─────────────────────────────────────────────────────────────────
# Two rules keep glibc from poisoning the rest of the shell:
#   * LD_PRELOAD is dropped — Termux sets it to bionic libs that the glibc loader rejects
#   * LD_LIBRARY_PATH is passed to opencode only, never exported globally
say "writing launcher"
cat > "$PREFIX/bin/opencode" <<'LAUNCHER'
#!/data/data/com.termux/files/usr/bin/bash
# opencode launcher for Termux. Runs the glibc-linked binary through Termux's glibc loader.
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
GLIBC="$PREFIX/glibc/lib"
BIN="$PREFIX/share/opencode/opencode.real"

[ -x "$BIN" ] || { echo "opencode: binary missing at $BIN — re-run install.sh" >&2; exit 1; }
[ -x "$GLIBC/ld-linux-aarch64.so.1" ] || {
  echo "opencode: glibc runtime missing — run: pkg install glibc-repo && pkg install glibc glibc-runner" >&2
  exit 1
}

# Android has no /tmp, and Bun unpacks its native TUI module somewhere writable.
export TMPDIR="${TMPDIR:-$PREFIX/tmp}"
mkdir -p "$TMPDIR"

# Do NOT run through the loader by hand: process.execPath would become the
# loader, and opencode re-execs itself (`serve`) for its background server.
# The binary's ELF interpreter already points at glibc, so exec it directly.
export LD_PRELOAD=
unset LD_LIBRARY_PATH || true
exec "$BIN" "$@"
LAUNCHER
chmod 755 "$PREFIX/bin/opencode"
ok "$PREFIX/bin/opencode"

# ── verify ───────────────────────────────────────────────────────────────────
say "verifying"
if V="$("$PREFIX/bin/opencode" --version 2>&1)"; then
  ok "opencode $V"
else
  warn "the binary did not report a version:"
  printf '%s\n' "$V" | sed 's/^/    /'
  cat <<'EOF'

  Common causes:
    bad ELF magic          -> LD_LIBRARY_PATH leaked into your shell. Run: unset LD_LIBRARY_PATH
    required file not found -> glibc runtime incomplete. Run: pkg install glibc glibc-runner
    Bad system call         -> old Android (10/11) seccomp. Try: pkg install glibc-runner, reboot
EOF
  exit 1
fi

cat <<EOF

$(printf "%b" "$G")done$(printf "%b" "$N")

  Run it:
    mkdir -p ~/code && cd ~/code   # any folder you like
    opencode

  Then type /connect and give it a base URL, API key and model.
  Nothing else to choose — this build has the custom-endpoint dialog only.

  Config:      ~/.config/opencode/opencode.jsonc
  UI settings: ~/.config/opencode/cli.json
  Uninstall:   rm -f \$PREFIX/bin/opencode && rm -rf \$PREFIX/share/opencode

EOF
