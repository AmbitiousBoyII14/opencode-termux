#!/bin/sh
# DeepSeek spend tracker.
#   sh ~/zai/burn.sh           balance, spend since reset, projection
#   sh ~/zai/burn.sh --reset   start the meter from the current balance
DIR="$HOME/zai"
STATE="$DIR/.burn-state"
LOG="$DIR/levi.log"

KEY=$(grep -m1 '^deepseek=' "$DIR/keys.txt" 2>/dev/null | cut -d= -f2- | tr -d ' \r\n')
if [ -z "$KEY" ]; then
  echo "no deepseek= line in $DIR/keys.txt"; exit 1
fi

BAL=$(curl -fsS -m 20 https://api.deepseek.com/user/balance \
      -H "Authorization: Bearer $KEY" 2>/dev/null \
      | sed -n 's/.*"total_balance":"\([0-9.]*\)".*/\1/p' | head -1)
if [ -z "$BAL" ]; then echo "could not read balance (network or key)"; exit 1; fi

case "$1" in
  --reset) echo "$BAL" > "$STATE"; echo "meter reset at \$$BAL"; exit 0 ;;
esac

[ -f "$STATE" ] || echo "$BAL" > "$STATE"
START=$(cat "$STATE")
TURNS=$(grep -c "served by deepseek" "$LOG" 2>/dev/null || echo 0)

exec python3 - "$BAL" "$START" "$TURNS" <<'PY'
import sys, datetime
now, start, turns = float(sys.argv[1]), float(sys.argv[2]), int(sys.argv[3])
spent = start - now

u = datetime.datetime.now(datetime.timezone.utc)
sast = u.astimezone(datetime.timezone(datetime.timedelta(hours=2)))
peak = u.weekday() < 5 and ((1 <= u.hour < 4) or (6 <= u.hour < 10))

print("=" * 52)
print(f"  balance now      ${now:.2f}")
print(f"  meter started    ${start:.2f}")
print(f"  spent since      ${spent:.4f}")
print(f"  requests logged  {turns}  (proxy log, since last restart)")
print(f"  right now        {'PEAK - full price' if peak else 'OFF-PEAK - half price'}"
      f"   ({sast:%a %H:%M} SAST)")
print("=" * 52)

RATE = 0.30 / 1e6 * 0.06 + 0.006 / 1e6 * 0.94 + 450 * 1.20 / 1e6
CTX = [("3K", 3000), ("10K", 10000), ("25K", 25000), ("50K", 50000), ("85K", 85000)]

def turn(ctx, peak=True):
    hit = ctx * 0.94
    miss = ctx * 0.06
    c = (miss * 0.30 + hit * 0.006 + 450 * 1.20) / 1e6
    return c if peak else c / 2

print("\n  24h CONTINUOUS  (1 message every 2 min = 720/day)")
print(f"  {'context':>8}{'$/day peak':>13}{'$ left':>10}{'days left':>11}{'$/day offpk':>14}{'days':>8}")
for lbl, c in CTX:
    d = turn(c) * 720
    o = turn(c, False) * 720
    print(f"  {lbl:>8}{d:>12.2f}{now:>10.2f}{now/d:>11.1f}{o:>13.2f}{now/o:>8.1f}")

print("\n  NORMAL USE")
for lbl, n in [("light 30 msg/day", 30), ("modding 150 msg/day", 150), ("heavy 400 msg/day", 400)]:
    d = turn(10000) * n
    print(f"  {lbl:<22} ${d:.3f}/day   {now/d:.0f} days")

if spent > 0.001:
    print(f"\n  YOUR ACTUAL RATE SO FAR: ${spent:.4f} spent")
    print(f"  at that burn, ${now:.2f} lasts {now/(spent):.1f} more 'same periods'")
PY
