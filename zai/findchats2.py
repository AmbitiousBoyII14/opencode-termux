#!/usr/bin/env python3
"""Find EVERY opencode chat store on the device, not just the one we expect.

opencode has used at least three layouts:
  2.x        sqlite  ~/.local/share/opencode/opencode.db   (table: session_v2)
  older 1.x  sqlite  ~/.local/state/opencode/opencode.db   (table: session)
  1.x        json    ~/.local/share/opencode/project/<hash>/storage/session/
This scans all of them and reports what it finds, with date ranges.
"""
import os
import sqlite3
import datetime as dt

ROOTS = [os.path.expanduser("~/.local"), os.path.expanduser("~/.config"),
         os.path.expanduser("~/.cache/opencode")]
DBS = {"session", "session_v2"}


def when(ts):
    try:
        return dt.datetime.fromtimestamp(ts / 1000).strftime("%d %b %H:%M")
    except Exception:
        return "?"


def scan_sqlite(path):
    try:
        con = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
        cur = con.cursor()
        tables = [r[0] for r in cur.execute(
            "select name from sqlite_master where type='table'")]
        hit = [t for t in tables if t in DBS]
        if not hit:
            con.close()
            return None
        t = hit[0]
        cols = [r[1] for r in cur.execute(f"PRAGMA table_info({t})")]
        n = cur.execute(f"select count(*) from {t}").fetchone()[0]
        col = "time_updated" if "time_updated" in cols else (
            "time_created" if "time_created" in cols else None)
        lo = hi = None
        if col:
            r = cur.execute(f"select min({col}), max({col}) from {t}").fetchone()
            lo, hi = r[0], r[1]
        con.close()
        return {"table": t, "count": n, "first": when(lo) if lo else "?",
                "last": when(hi) if hi else "?"}
    except Exception as e:
        return {"error": str(e)[:60]}


def scan_json_store(d):
    """1.x JSON layout: storage/session/info/*.json"""
    info = os.path.join(d, "info")
    if not os.path.isdir(info):
        return None
    files = [f for f in os.listdir(info) if f.endswith(".json")]
    if not files:
        return None
    times = []
    for f in files:
        try:
            times.append(os.path.getmtime(os.path.join(info, f)))
        except OSError:
            pass
    lo = dt.datetime.fromtimestamp(min(times)).strftime("%d %b %H:%M") if times else "?"
    hi = dt.datetime.fromtimestamp(max(times)).strftime("%d %b %H:%M") if times else "?"
    return {"count": len(files), "first": lo, "last": hi, "path": d}


def main():
    found = False
    print("=== SQLite databases ===")
    for root in ROOTS:
        if not os.path.isdir(root):
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in ("node_modules", "bin")]
            for f in filenames:
                if not f.endswith(".db"):
                    continue
                p = os.path.join(dirpath, f)
                r = scan_sqlite(p)
                if r is None:
                    continue
                found = True
                if "error" in r:
                    print(f"  {p}\n     !! {r['error']}")
                else:
                    print(f"  {p}")
                    print(f"     table {r['table']}: {r['count']} session(s), "
                          f"{r['first']} -> {r['last']}")

    print("\n=== JSON session stores (1.x layout) ===")
    any_json = False
    for root in ROOTS:
        if not os.path.isdir(root):
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            if os.path.basename(dirpath) == "session":
                r = scan_json_store(dirpath)
                if r:
                    any_json = True
                    found = True
                    print(f"  {r['path']}")
                    print(f"     {r['count']} session file(s), {r['first']} -> {r['last']}")
    if not any_json:
        print("  none")

    if not found:
        print("\nnothing found. check:  ls -la ~/.local/share/opencode/")
    print("\nNewest data wins - open whichever store has your recent dates.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
