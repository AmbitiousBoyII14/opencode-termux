#!/bin/sh
# Recover an opencode chat database whose -wal file was left behind.
# Fixes: "Database is not empty and has no session table"
set -e
DEST="$HOME/storage/shared/levi-backup"
OCDIR="$HOME/.local/share/opencode"

LATEST=$(ls -t "$DEST"/levi-backup-*.tar.gz 2>/dev/null | head -1)
[ -n "$LATEST" ] || { echo "!! no backup in $DEST"; exit 1; }
echo "backup: $(basename "$LATEST")"

mkdir -p "$HOME/.cache"
W="$HOME/.cache/fixdb-$$"
rm -rf "$W"; mkdir -p "$W"
tar -xzf "$LATEST" -C "$W"
SRC=$(ls -d "$W"/levi-bk-* | head -1)

echo "--- files in the backup ---"
ls -la "$SRC/opencode/" | awk 'NR>1{printf "   %-24s %s bytes\n",$9,$5}'

mkdir -p "$OCDIR"
# keep whatever is there now, just in case
[ -f "$OCDIR/opencode.db" ] && cp "$OCDIR/opencode.db" "$OCDIR/opencode.db.broken.$(date +%s)"

if [ -f "$SRC/opencode/opencode.db-wal" ]; then
  echo "--- restoring db + wal + shm together ---"
  cp "$SRC/opencode/opencode.db"     "$OCDIR/opencode.db"
  cp "$SRC/opencode/opencode.db-wal" "$OCDIR/opencode.db-wal"
  [ -f "$SRC/opencode/opencode.db-shm" ] && cp "$SRC/opencode/opencode.db-shm" "$OCDIR/opencode.db-shm"
else
  echo "--- backup has no -wal; copying the db alone ---"
  cp "$SRC/opencode/opencode.db" "$OCDIR/opencode.db"
fi

echo "--- checkpointing the WAL into the main db ---"
N=""
if command -v sqlite3 >/dev/null 2>&1; then
  sqlite3 "$OCDIR/opencode.db" "PRAGMA wal_checkpoint(TRUNCATE);" >/dev/null 2>&1 || true
  sqlite3 "$OCDIR/opencode.db" ".tables" | sed 's/^/   tables: /'
  N=$(sqlite3 "$OCDIR/opencode.db" "select count(*) from session;" 2>/dev/null || echo "")
fi
if [ -z "$N" ] && command -v python3 >/dev/null 2>&1; then
  N=$(python3 - "$OCDIR/opencode.db" <<'PYEOF'
import sqlite3, sys
try:
    c = sqlite3.connect(sys.argv[1])
    c.execute("PRAGMA wal_checkpoint(TRUNCATE);")
    n = c.execute("select count(*) from session;").fetchone()[0]
    print(n)
except Exception:
    print("")
PYEOF
)
  [ -n "$N" ] && echo "   sessions: $N  (via python3)"
fi
rm -rf "$W"

echo
if [ -n "$N" ] && [ "$N" -gt 0 ] 2>/dev/null; then
  echo "================ FIXED ================"
  echo "  $N conversations recovered"
  echo "  run:  opencode --continue"
  echo "======================================="
elif [ "$N" = "0" ]; then
  echo "!! db opened fine but contains 0 sessions."
  echo "   Your chats may predate the backup. Nothing else to recover."
else
  echo "!! could not read a session table."
  echo "   send me:  ls -la $OCDIR"
fi
