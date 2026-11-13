#!/usr/bin/env python3
"""DeepSeek spend tracker.

  python3 burn.py            balance, exact measured spend, projection
  python3 burn.py --reset    start the meter from the current balance

Reads exact token usage written by levi-proxy.py to levi-usage.log, so the
"spent" figure is measured, not estimated.
"""
import json
import os
import sys
import urllib.request
import datetime as dt

DIR = os.path.dirname(os.path.abspath(__file__))
KEYS = os.path.join(DIR, "keys.txt")
STATE = os.path.join(DIR, ".burn-state")
USAGE = os.path.join(DIR, "levi-usage.log")

# DeepSeek V4.1-Flash, peak rates, USD per token
IN_MISS = 0.30 / 1e6
IN_HIT = 0.006 / 1e6
OUT = 1.20 / 1e6


def deepseek_key():
    try:
        for line in open(KEYS):
            if line.startswith("deepseek="):
                return line.split("=", 1)[1].strip()
    except OSError:
        return None
    return None


def balance(key):
    req = urllib.request.Request(
        "https://api.deepseek.com/user/balance",
        headers={"Authorization": "Bearer " + key},
    )
    with urllib.request.urlopen(req, timeout=20) as r:
        d = json.loads(r.read())
    return float(d["balance_infos"][0]["total_balance"])


def measured_spend():
    """Exact cost of every request this proxy has served."""
    tot, n, tin, tout = 0.0, 0, 0, 0
    try:
        for line in open(USAGE):
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            tot += rec.get("cost", 0.0)
            tin += rec.get("in", 0)
            tout += rec.get("out", 0)
            n += 1
    except OSError:
        pass
    return tot, n, tin, tout


def turn_cost(ctx, out_tok=450, peak=True):
    hit = ctx * 0.94
    miss = ctx * 0.06
    c = miss * IN_MISS + hit * IN_HIT + out_tok * OUT
    return c if peak else c / 2


def main():
    key = deepseek_key()
    if not key:
        print("no deepseek= line in", KEYS)
        return 1

    try:
        bal = balance(key)
    except Exception as e:
        print("could not read balance:", e)
        return 1

    if "--reset" in sys.argv:
        open(STATE, "w").write(f"{bal}\n")
        print(f"meter reset at ${bal:.2f}")
        return 0

    start = bal
    try:
        start = float(open(STATE).read().strip())
    except (OSError, ValueError):
        open(STATE, "w").write(f"{bal:.2f}\n")

    spent, n, tin, tout = measured_spend()

    u = dt.datetime.now(dt.timezone.utc)
    sast = u.astimezone(dt.timezone(dt.timedelta(hours=2)))
    peak = u.weekday() < 5 and ((1 <= u.hour < 4) or (6 <= u.hour < 10))

    print("=" * 56)
    print(f"  balance now       ${bal:.2f}")
    print(f"  meter started     ${start:.2f}")
    print(f"  balance drop      ${start - bal:.4f}")
    print(f"  MEASURED spend    ${spent:.5f}  over {n} requests")
    if n:
        print(f"  tokens            {tin:,} in / {tout:,} out")
        print(f"  avg per request   ${spent / n:.5f}")
    print(f"  right now         {'PEAK  full price' if peak else 'OFF-PEAK  half price'}"
          f"   ({sast:%a %H:%M} SAST)")
    print("=" * 56)

    print("\n  24h CONTINUOUS  (1 message every 2 min = 720/day)")
    print(f"  {'context':>8}{'$/day':>10}{'days left':>12}{'off-peak $/day':>17}{'days':>8}")
    for lbl, ctx in [("3K", 3000), ("10K", 10000), ("25K", 25000),
                     ("50K", 50000), ("85K", 85000)]:
        d = turn_cost(ctx) * 720
        o = turn_cost(ctx, peak=False) * 720
        print(f"  {lbl:>8}{d:>10.2f}{bal / d:>12.1f}{o:>17.2f}{bal / o:>8.1f}")

    print("\n  NORMAL USE  (context ~10K)")
    for lbl, k in [("light 30 msg/day", 30), ("modding 150 msg/day", 150),
                   ("heavy 400 msg/day", 400)]:
        d = turn_cost(10000) * k
        print(f"  {lbl:<22} ${d:.3f}/day   {bal / d:.0f} days")

    if spent > 0.0005:
        print(f"\n  At your measured rate (${spent:.5f} for {n} requests):")
        print(f"    ${bal / (spent / n):,.0f} more requests on ${bal:.2f}")
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
