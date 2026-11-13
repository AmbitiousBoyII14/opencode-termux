#!/bin/sh
# Back up everything worth keeping OUT of Termux, to shared storage.
# Survives uninstall / reinstall / factory reset of the Termux app.
set -e

DEST="$HOME/storage/shared/levi-backup"
STAMP=$(date +%Y%m%d-%H%M)
WORK="/tmp/levi-bk-$STAMP"

if [ ! -d "$HOME/storage/shared" ]; then
  echo "!! shared storage not mounted."
  echo "   Run:  termux-setup-storage"
  echo "   (tap Allow on the Android popup, then run this again)"
  exit 1
fi

mkdir -p "$WORK/opencode" "$WORK/zai" "$DEST"

echo "==> opencode chat database"
DB=""
for c in "$HOME/.local/share/opencode/opencode.db" \
         "$HOME/.local/state/opencode/opencode.db"; do
  [ -f "$c" ] && DB="$c" && break
done

if [ -n "$DB" ]; then
  SZ=$(du -h "$DB" | cut -f1)
  echo "    found: $DB ($SZ)"
  if command -v sqlite3 >/dev/null 2>&1; then
    echo "    using sqlite3 .backup (safe while opencode is running)"
    sqlite3 "$DB" ".backup '$WORK/opencode/opencode.db'"
  else
    echo "    sqlite3 not installed, copying raw + WAL"
    cp "$DB" "$WORK/opencode/opencode.db"
    [ -f "$DB-wal" ] && cp "$DB-wal" "$WORK/opencode/opencode.db-wal"
    [ -f "$DB-shm" ] && cp "$DB-shm" "$WORK/opencode/opencode.db-shm"
  fi
  echo "    backed up: $(du -h "$WORK/opencode/opencode.db" | cut -f1)"
else
  echo "    !! no opencode.db found - nothing to back up"
fi

echo "==> opencode config"
[ -f "$HOME/.config/opencode/opencode.json" ] && \
  cp "$HOME/.config/opencode/opencode.json" "$WORK/opencode/" && echo "    opencode.json"

echo "==> levi proxy keys + prompt"
for f in keys.txt levi-system-prompt.md; do
  [ -f "$HOME/zai/$f" ] && cp "$HOME/zai/$f" "$WORK/zai/" && echo "    zai/$f"
done
[ -f "$HOME/.bashrc" ] && cp "$HOME/.bashrc" "$WORK/bashrc"

echo "==> your work (not included - lives in shared storage already)"
for d in "$HOME/storage/downloads" "$HOME/projects" "$HOME/mod" "$HOME/storage/shared/Download"; do
  [ -d "$d" ] && echo "    $d survives the uninstall (it is outside Termux)"
done

echo "==> packing"
cd /tmp
tar -czf "$DEST/levi-backup-$STAMP.tar.gz" "levi-bk-$STAMP"
rm -rf "$WORK"

OUT="$DEST/levi-backup-$STAMP.tar.gz"
echo
echo "================ BACKUP OK ================"
echo "  file   $OUT"
echo "  size   $(du -h "$OUT" | cut -f1)"
echo "  sha    $(sha256sum "$OUT" | cut -c1-16)..."
echo "==========================================="
echo
echo "  This lives at /sdcard/levi-backup/ and survives Termux uninstall."
echo "  Copy it to Google Drive if you want a second copy."
echo
echo "  AFTER reinstalling Termux run:"
echo "    pkg update -y && pkg install -y python curl sqlite"
echo "    termux-setup-storage"
echo "    curl -fsSL https://raw.githubusercontent.com/AmbitiousBoyII14/opencode-termux/main/zai/restore.sh | sh"
