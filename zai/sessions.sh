#!/bin/sh
# Find opencode sessions the /sessions picker hides, and print resume commands.
# Usage: sh ~/zai/sessions.sh
set -e

PY=python3
FOUND=0

emit() { # $1 = json array from opencode
  echo "$1" | $PY -c '
import sys,json,datetime
try:
    rows=json.load(sys.stdin)
except Exception:
    sys.exit(1)
if isinstance(rows,dict): rows=rows.get("data") or rows.get("sessions") or []
if not rows: sys.exit(1)
rows=sorted(rows,key=lambda r:r.get("time_updated") or r.get("timeUpdated") or 0,reverse=True)
print("\n  %-28s %-9s %s" % ("ID","WHEN","TITLE"))
print("  " + "-"*78)
for r in rows[:60]:
    t=r.get("time_updated") or r.get("timeUpdated") or 0
    when=datetime.datetime.fromtimestamp(t/1000).strftime("%d %b %H:%M") if t else "?"
    sid=r.get("id") or r.get("sessionID") or "?"
    title=(r.get("title") or r.get("slug") or "(untitled)")[:44]
    print("  %-28s %-9s %s" % (sid, when, title))
print()
print("  Resume one with:   opencode --session <ID>")
'
}

echo "==> opencode session list"
if OUT=$(opencode session list --format json 2>/dev/null); then
  emit "$OUT" && FOUND=1
fi

if [ "$FOUND" = "0" ]; then
  echo "    (that returned nothing - trying the raw database)"

  DB=$(opencode db path 2>/dev/null || echo "$HOME/.local/share/opencode/opencode.db")
  echo "    db: $DB"

  if [ -f "$DB" ]; then
    SQL="select id, title, time_updated, directory from session where parent_id is null order by time_updated desc limit 60;"
    if OUT=$(opencode db "$SQL" 2>/dev/null); then
      echo "$OUT"
    else
      echo "    opencode db failed, reading sqlite directly"
      command -v sqlite3 >/dev/null 2>&1 || pkg install -y sqlite >/dev/null 2>&1
      sqlite3 -header -column "$DB" "$SQL" 2>/dev/null || \
        $PY -c "
import sqlite3,sys
c=sqlite3.connect('$DB')
for r in c.execute(\"$SQL\"):
    print('  ',r)
"
    fi
    FOUND=1
  fi
fi

if [ "$FOUND" = "0" ]; then
  echo
  echo "  Nothing found. Send me the output of:"
  echo "    opencode debug paths"
  echo "    ls -la \$HOME/.local/share/opencode/"
  exit 1
fi

echo
echo "  Sessions live in:  \$HOME/.local/share/opencode/"
echo "  Pick the one you want and run:  opencode --session <ID>"
