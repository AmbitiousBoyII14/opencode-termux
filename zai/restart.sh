#!/bin/sh
# Restart the proxy with the current levi-proxy.py. Safe: never leaves two running.
echo "==> stopping"
pkill -f "python3 levi-proxy.py" 2>/dev/null && sleep 1
pkill -f "levi-proxy.py" 2>/dev/null; sleep 1
echo "==> starting"
cd "$HOME/zai" || exit 1
LEVI_MAX_TOKENS="${LEVI_MAX_TOKENS:-4096}" \
  setsid python3 levi-proxy.py >> "$HOME/zai/levi.log" 2>&1 < /dev/null &
for i in $(seq 1 20); do
  if curl -fsS -m 2 http://127.0.0.1:8080/health >/dev/null 2>&1; then
    echo -n "   up: "
    curl -s http://127.0.0.1:8080/health
    echo
    echo "   max_tokens cap: ${LEVI_MAX_TOKENS:-4096}   (big contexts get more)"
    exit 0
  fi
  sleep 1
done
echo "   did not start - see $HOME/zai/levi.log"; exit 1
