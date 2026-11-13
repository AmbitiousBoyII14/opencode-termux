#!/bin/sh
# backup.sh v3 - finds EVERY chat store, checkpoints WAL, then packs.
#
# What v2 got wrong:
#   - it only looked at two hardcoded db paths
#   - it copied a live WAL instead of checkpointing it first
#   - it never verified the session count
set -e
STAMP=$(date +%Y%m%d-%H%M)
DEST="$HOME/storage/shared/levi-backup"
STAGE="$HOME/.cache/levi-bk-$STAMP"

echo "backup.sh v3 ($STAMP)"
[ -d "$HOME/storage/shared" ] || { echo "!! run: termux-setup-storage"; exit 1; }

rm -rf "$STAGE"; mkdir -p "$STAGE/opencode" "$STAGE/zai" "$DEST"

TOTAL=0

# checkpoint a database into a single self-contained copy
save_db() {
  db="$1"; label="$2"
  [ -f "$db" ] || return 0
  out="$STAGE/opencode/$label.db"
  tmp="$HOME/.cache/_ck-$label.db"
  rm -f "$tmp"
  cp "$db" "$tmp"
  for e in -wal -shm; do [ -f "$db$e" ] && cp "$db$e" "$tmp$e"; done
  if command -v sqlite3 >/dev/null 2>&1; then
    sqlite3 "$tmp" "PRAGMA wal_checkpoint(TRUNCATE);" >/dev/null 2>&1 || true
  else
    python3 - "$tmp" <<'PY' 2>/dev/null || true
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("PRAGMA wal_checkpoint(TRUNCATE);")
c.commit(); c.close()
PY
  fi
  # after a TRUNCATE checkpoint the -wal is empty, so one file is the whole db
  cp "$tmp" "$out"
  rm -f "$tmp" "$tmp-wal" "$tmp-shm"
  N=$(python3 - "$out" <<'PY' 2>/dev/null || echo "?"
import sqlite3, sys
try:
    c = sqlite3.connect("file:%s?mode=ro" % sys.argv[1], uri=True)
    t = [r[0] for r in c.execute("select name from sqlite_master where type='table'")]
    tbl = "session_v2" if "session_v2" in t else ("session" if "session" in t else None)
    print(c.execute("select count(*) from %s" % tbl).fetchone()[0] if tbl else "?")
except Exception:
    print("?")
PY
)
  echo "    $label: $N session(s)  -> $out"
  case "$N" in ''|'?') ;; *) TOTAL=$((TOTAL + N)) ;; esac
}

echo "==> chat databases"
save_db "$HOME/.local/share/opencode/opencode.db" "share"
save_db "$HOME/.local/state/opencode/opencode.db"  "state"
save_db "$HOME/.opencode/opencode.db"              "dotopencode"

echo "==> 1.x JSON session stores"
for d in "$HOME/.local/share/opencode/project" "$HOME/.local/state/opencode"; do
  [ -d "$d" ] || continue
  find "$d" -type d -name session 2>/dev/null | while read -r s; do
    rel=$(echo "$s" | sed "s|$HOME/||; s|/|_|g")
    mkdir -p "$STAGE/opencode/json"
    tar -cf "$STAGE/opencode/json/$rel.tar" -C "$(dirname "$s")" session 2>/dev/null \
      && echo "    json store -> $rel.tar"
  done
done

echo "==> config + keys"
[ -f "$HOME/.config/opencode/opencode.json" ] && cp "$HOME/.config/opencode/opencode.json" "$STAGE/opencode/" && echo "    opencode.json"
for f in keys.txt levi-system-prompt.md; do
  [ -f "$HOME/zai/$f" ] && cp "$HOME/zai/$f" "$STAGE/zai/" && echo "    zai/$f"
done
[ -f "$HOME/.bashrc" ] && cp "$HOME/.bashrc" "$STAGE/bashrc"

echo "==> packing"
tar -czf "$DEST/levi-backup-$STAMP.tar.gz" -C "$HOME/.cache" "levi-bk-$STAMP"
rm -rf "$STAGE"
OUT="$DEST/levi-backup-$STAMP.tar.gz"

echo
echo "================ BACKUP OK ================"
echo "  file      $OUT"
echo "  size      $(du -h "$OUT" | cut -f1)"
echo "  sessions  $TOTAL total across all stores"
echo "==========================================="
if [ "$TOTAL" -eq 0 ] 2>/dev/null; then
  echo "  !! WARNING: zero sessions found. This backup is empty of chats."
fi
