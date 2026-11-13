#!/usr/bin/env python3
"""List every session in the opencode database, ignoring TUI filters.

The 2.x /sessions picker scopes to the current project directory and hides
archived / subagent sessions. This reads the database directly so nothing is
invisible.
"""
import os
import sqlite3
import sys
import datetime as dt

CANDIDATES = [
    os.path.expanduser("~/.local/share/opencode/opencode.db"),
    os.path.expanduser("~/.local/state/opencode/opencode.db"),
]


def find_db():
    for p in CANDIDATES:
        if os.path.exists(p):
            return p
    return None


def cols(cur, table):
    try:
        return [r[1] for r in cur.execute(f"PRAGMA table_info({table})")]
    except sqlite3.Error:
        return []


def pick(c, *names):
    """First column that exists, else None."""
    for n in names:
        if n in c:
            return n
    return None


def main():
    db = find_db()
    if not db:
        print("no opencode.db found in:")
        for p in CANDIDATES:
            print("   ", p)
        return 1

    print(f"db: {db}  ({os.path.getsize(db)/1048576:.1f} MB)")
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    cur = con.cursor()

    tables = {r[0] for r in cur.execute(
        "select name from sqlite_master where type='table'")}
    t = "session_v2" if "session_v2" in tables else ("session" if "session" in tables else None)
    if not t:
        print("no session table. tables present:", ", ".join(sorted(tables)))
        return 1

    c = cols(cur, t)
    cid = pick(c, "id")
    ctitle = pick(c, "title", "slug")
    cdir = pick(c, "directory", "path")
    cparent = pick(c, "parent_id")
    ct = pick(c, "time_updated", "time_created")
    carch = pick(c, "time_archived")

    sel = [x for x in (cid, ctitle, cdir, cparent, ct, carch) if x]
    rows = list(cur.execute(f"select {', '.join(sel)} from {t}"))
    idx = {n: i for i, n in enumerate(sel)}

    total = len(rows)
    roots = [r for r in rows if not (cparent and r[idx[cparent]])]
    print(f"sessions: {total} total, {len(roots)} top-level\n")

    roots.sort(key=lambda r: (r[idx[ct]] if ct and r[idx[ct]] else 0), reverse=True)

    bydir = {}
    for r in roots:
        d = (r[idx[cdir]] if cdir else "") or "(no directory)"
        bydir.setdefault(d, []).append(r)

    for d, items in sorted(bydir.items(), key=lambda kv: -len(kv[1])):
        print(f"  {d}   [{len(items)} chat(s)]")
        for r in items[:40]:
            sid = r[idx[cid]]
            title = (r[idx[ctitle]] if ctitle else None) or "(untitled)"
            ts = r[idx[ct]] if ct else None
            when = dt.datetime.fromtimestamp(ts / 1000).strftime("%d %b %H:%M") if ts else "?"
            flags = ""
            if carch and r[idx[carch]]:
                flags += " [archived]"
            print(f"    {when:<12} {title[:44]:<46} {sid}{flags}")
        if len(items) > 40:
            print(f"    ... {len(items)-40} more")
        print()

    print("open one with:   opencode -s <id>")
    print("or from its dir: cd <directory> && opencode --continue")
    con.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
