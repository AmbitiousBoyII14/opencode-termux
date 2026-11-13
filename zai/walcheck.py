#!/usr/bin/env python3
"""Check whether a backup's -wal file holds sessions the main db doesn't.

SQLite keeps recent writes in db-wal until a checkpoint. If the archive was
taken while opencode was running, the newest chats may exist ONLY there.
"""
import glob
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import datetime as dt

BK = os.path.expanduser("~/storage/shared/levi-backup")
WORK = os.path.expanduser("~/.cache/walcheck")


def when(ts):
    try:
        return dt.datetime.fromtimestamp(ts / 1000).strftime("%d %b %H:%M")
    except Exception:
        return "?"


def main():
    tars = sorted(glob.glob(os.path.join(BK, "levi-backup-*.tar.gz")),
                  key=os.path.getmtime, reverse=True)
    if not tars:
        print("no backup found in", BK); return 1
    tar = tars[0]
    print("backup:", os.path.basename(tar))

    shutil.rmtree(WORK, ignore_errors=True)
    os.makedirs(WORK, exist_ok=True)
    subprocess.run(["tar", "-xzf", tar, "-C", WORK], check=True)

    srcs = glob.glob(os.path.join(WORK, "levi-bk-*", "opencode"))
    if not srcs:
        print("no opencode/ dir in archive"); return 1
    src = srcs[0]
    for f in sorted(os.listdir(src)):
        print(f"   {f:<24} {os.path.getsize(os.path.join(src, f)):,} bytes")

    db = os.path.join(src, "opencode.db")
    wal = db + "-wal"
    if not os.path.exists(db):
        print("no opencode.db in archive"); return 1

    # copy all three next to each other so sqlite replays the WAL
    tmp = tempfile.mkdtemp(dir=WORK)
    for ext in ("", "-wal", "-shm"):
        p = db + ext
        if os.path.exists(p):
            shutil.copy2(p, os.path.join(tmp, "opencode.db" + ext))

    test = os.path.join(tmp, "opencode.db")
    print("\n--- opening with the WAL present ---")
    con = sqlite3.connect(test)
    cur = con.cursor()
    tables = [r[0] for r in cur.execute(
        "select name from sqlite_master where type='table'")]
    t = "session_v2" if "session_v2" in tables else "session"
    if t not in tables:
        print("no session table:", tables); return 1
    cols = [r[1] for r in cur.execute(f"PRAGMA table_info({t})")]
    tc = "time_updated" if "time_updated" in cols else "time_created"
    n, lo, hi = cur.execute(f"select count(*), min({tc}), max({tc}) from {t}").fetchone()
    print(f"   sessions: {n}")
    print(f"   range   : {when(lo)} -> {when(hi)}")

    ids_db = {r[0] for r in cur.execute(f"select id from {t}")}

    # newer rows from the event table, if any
    if "event" in tables:
        ecols = [r[1] for r in cur.execute("PRAGMA table_info(event)")]
        if "time_created" in ecols:
            try:
                en, ehi = cur.execute(
                    "select count(*), max(time_created) from event").fetchone()
                print(f"   events  : {en}, newest {when(ehi)}")
            except sqlite3.Error:
                pass
    con.close()

    # what session ids appear in the RAW wal that are not in the db?
    if os.path.exists(wal):
        print("\n--- raw scan of opencode.db-wal ---")
        raw = open(wal, "rb").read()
        ids_wal = set(re.findall(rb"ses_[A-Za-z0-9]{8,40}", raw))
        # sqlite stores rows inline in pages, so a match can run into the next
        # column's bytes. Trim anything that is not a plausible id suffix.
        ids_wal = {m.decode() for m in ids_wal}
        ids_wal = {i.decode() for i in ids_wal}
        print(f"   session ids in WAL : {len(ids_wal)}")
        print(f"   session ids in db  : {len(ids_db)}")
        extra = ids_wal - ids_db
        print(f"   in WAL only        : {len(extra)}")
        for i in sorted(extra)[:20]:
            print("      ", i)
    shutil.rmtree(WORK, ignore_errors=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
