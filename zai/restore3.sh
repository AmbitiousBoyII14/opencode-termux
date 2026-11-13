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
if [ -z "$LATEST" ]; then
  echo "!! no levi-backup-*.tar.gz in $DEST"
  echo "   Continuing WITHOUT your old chats - everything else still installs."
  LATEST=""
fi

if [ -n "$LATEST" ]; then

echo "==> restoring from $(basename "$LATEST")"
mkdir -p "$HOME/.cache"
WORK="$HOME/.cache/levi-restore-$$"
rm -rf "$WORK"; mkdir -p "$WORK"
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
else
  echo "    skipping chat restore"
fi

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
mkdir -p "$HOME/.config/opencode"
cat > "$HOME/.config/opencode/opencode.json" <<'JSON'
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "levi": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Levi",
      "options": { "baseURL": "http://127.0.0.1:8080/v1", "apiKey": "unused" },
      "models": {
        "deepseek-flash": {
          "name": "Levi - DeepSeek (paid)",
          "limit": { "context": 131072, "output": 8192 }
        },
        "nemotron-ultra": {
          "name": "Levi - Nemotron 550B (free)",
          "limit": { "context": 131072, "output": 8192 }
        }
      }
    }
  },
  "model": "levi/deepseek-flash"
}
JSON
echo "    opencode.json written (2 models)"

echo "==> starting proxy"
[ -x "$HOME/zai/cheap.sh" ] && sh "$HOME/zai/cheap.sh" || echo "    cheap.sh missing - start manually with: cd ~/zai && python3 levi-proxy.py"

echo
echo "================ RESTORE DONE ================"
[ -f "$HOME/.local/share/opencode/opencode.db" ] && \
  echo "  chats    restored ($(du -h "$HOME/.local/share/opencode/opencode.db" | cut -f1))" || \
  echo "  chats    NONE - no backup found, starting fresh"
[ -f "$HOME/zai/keys.txt" ] && \
  echo "  keys     $(grep -c . "$HOME/zai/keys.txt") provider(s): $(cut -d= -f1 "$HOME/zai/keys.txt" | paste -sd' ')" || \
  echo "  keys     MISSING - add: echo 'deepseek=sk-...' >> ~/zai/keys.txt"
echo
echo "  Start:      opencode"
echo "  Old chats:  opencode --continue     (or /sessions inside)"
