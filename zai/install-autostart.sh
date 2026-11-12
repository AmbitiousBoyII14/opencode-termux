#!/bin/sh
# Make the Levi proxy start automatically in Termux.
#   curl -fsSL .../zai/install-autostart.sh | sh
set -e
RAW="https://raw.githubusercontent.com/AmbitiousBoyII14/opencode-termux/main/zai"
DIR="$HOME/zai"
BASHRC="$HOME/.bashrc"

echo "==> getting start.sh"
mkdir -p "$DIR"
curl -fsSL -o "$DIR/start.sh" "$RAW/start.sh"
chmod +x "$DIR/start.sh"

echo "==> getting Termux:Boot script"
curl -fsSL -o "$DIR/boot.sh" "$RAW/boot.sh"
chmod +x "$DIR/boot.sh"

echo "==> boot hook"
BOOTDIR="$HOME/.termux/boot"
mkdir -p "$BOOTDIR"
cp "$DIR/boot.sh" "$BOOTDIR/levi-proxy"
chmod +x "$BOOTDIR/levi-proxy"
echo "    $BOOTDIR/levi-proxy"

echo "==> shell hook (.bashrc)"
if grep -q "zai/start.sh" "$BASHRC" 2>/dev/null; then
  echo "    already present"
else
  {
    echo ""
    echo "# Levi proxy - start on shell open (silent, no-op if already running)"
    echo '[ -x "$HOME/zai/start.sh" ] && "$HOME/zai/start.sh" >/dev/null 2>&1'
  } >> "$BASHRC"
  echo "    added"
fi

echo "==> starting now"
"$DIR/start.sh" && echo "    running" || echo "    failed - check $DIR/levi.log"

echo
echo "Done. The proxy now starts:"
echo "  - every time Termux boots   (needs the Termux:Boot app - see below)"
echo "  - every time you open a new Termux shell  (already active)"
echo
echo "Termux:Boot is a small add-on app. Install it once from F-Droid/Play,"
echo "open it once, and your phone reboot will auto-start the proxy."
echo "Without it, the .bashrc hook still covers every shell you open."
