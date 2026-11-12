#!/bin/sh
# Start the Levi proxy unless it's already answering.
# Safe to run as often as you like - it never starts a second copy.
DIR="$HOME/zai"
URL="http://127.0.0.1:8080/health"

if curl -fsS -m 3 "$URL" >/dev/null 2>&1; then
  exit 0                       # already up
fi

# clear any half-dead process
pkill -f levi-proxy.py 2>/dev/null
sleep 1

cd "$DIR" || exit 1
nohup python3 levi-proxy.py >> "$DIR/levi.log" 2>&1 &

# wait up to 20s for it to answer
for i in $(seq 1 20); do
  curl -fsS -m 2 "$URL" >/dev/null 2>&1 && exit 0
  sleep 1
done

echo "levi proxy did not start; see $DIR/levi.log" >&2
exit 1
