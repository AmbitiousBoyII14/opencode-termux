#!/bin/sh
# Restore after a Termux reinstall. Run AFTER:
#   pkg update -y && pkg install -y python curl sqlite && termux-setup-storage
set -e
DEST="$HOME/storage/shared/levi-backup"

if [ ! -d "$DEST" ]; then
  echo "!! nothing at $DEST"
  echo "   Run termux-setup-storage first, or copy your backup folder back."
  exit 1
fi

LATEST=$(ls -t "$DEST"/levi-backup-*.tar.gz 2>/dev/null | head -1)
[ -n "$LATEST" ] || { echo "!! no levi-backup-*.tar.gz in $DEST"; exit 1; }

echo "==> restoring from $(basename "$LATEST")"
WORK=$(mktemp -d)
tar -xzf "$LATEST" -C "$WORK"
SRC=$(ls -d "$WORK"/levi-bk-* | head -1)

mkdir -p "$HOME/.config/opencode" "$HOME/.local/share/opencode" "$HOME/zai"

if [ -f "$SRC/opencode/opencode.db" ]; then
  cp "$SRC/opencode/opencode.db" "$HOME/.local/share/opencode/opencode.db"
  echo "    chat database restored ($(du -h "$HOME/.local/share/opencode/opencode.db" | cut -f1))"
fi
[ -f "$SRC/opencode/opencode.json" ] && cp "$SRC/opencode/opencode.json" "$HOME/.config/opencode/" && echo "    opencode.json restored"
for f in keys.txt levi-system-prompt.md; do
  [ -f "$SRC/zai/$f" ] && cp "$SRC/zai/$f" "$HOME/zai/" && echo "    zai/$f restored"
done
[ -f "$HOME/zai/keys.txt" ] && chmod 600 "$HOME/zai/keys.txt"
[ -f "$SRC/bashrc" ] && cp "$SRC/bashrc" "$HOME/.bashrc" && echo "    .bashrc restored"
rm -rf "$WORK"

echo "==> pulling proxy + scripts"
RAW="https://raw.githubusercontent.com/AmbitiousBoyII14/opencode-termux/main/zai"
for f in levi-proxy.py start.sh cheap.sh burn.py install-models.sh; do
  curl -fsSL -o "$HOME/zai/$f" "$RAW/$f" && echo "    $f"
done
chmod +x "$HOME/zai/start.sh" "$HOME/zai/cheap.sh" 2>/dev/null || true

echo "==> installing opencode"
if command -v opencode >/dev/null 2>&1; then
  echo "    already installed: $(opencode --version 2>/dev/null || echo '?')"
else
  pkg install -y nodejs-lts 2>/dev/null || pkg install -y nodejs
  npm install -g opencode-ai
fi

echo "==> registering models"
sh "$HOME/zai/install-models.sh"

echo "==> starting proxy"
sh "$HOME/zai/cheap.sh"

echo
echo "================ RESTORE DONE ================"
echo "  opencode          : $(command -v opencode || echo MISSING)"
echo "  chats             : $(ls -la "$HOME/.local/share/opencode/opencode.db" 2>/dev/null | awk '{print $5" bytes"}' || echo none)"
echo
echo "  Start it:   opencode"
echo "  Old chats:  opencode --continue     or     /sessions"
