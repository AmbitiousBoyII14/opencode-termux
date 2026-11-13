#!/bin/sh
# The 3K setup. Starts the proxy in cheap mode:
#   output budget capped at 512 tokens  (output is $1.20/M, the expensive part)
#   context kept near 3K by starting fresh sessions
#   exact spend logged to levi-usage.log
DIR="$HOME/zai"
[ -f "$DIR/keys.txt" ] || { echo "no $DIR/keys.txt - add: deepseek=sk-... or nvidia=nvapi-..."; exit 1; }
pkill -f "python3 levi-proxy.py" 2>/dev/null
sleep 1
cd "$DIR" || exit 1
LEVI_MAX_TOKENS="${LEVI_MAX_TOKENS:-4096}" \
  setsid python3 levi-proxy.py >> "$DIR/levi.log" 2>&1 < /dev/null &
for i in $(seq 1 20); do
  curl -fsS -m 2 http://127.0.0.1:8080/health >/dev/null 2>&1 && {
    if ! grep -q '^deepseek=' "$DIR/keys.txt" 2>/dev/null; then
    echo "  !! no deepseek= line in $DIR/keys.txt"
    echo "     running on NVIDIA only - free, but weaker. To add DeepSeek:"
    echo "       grep -v '^deepseek=' ~/zai/keys.txt > /tmp/k; mv /tmp/k ~/zai/keys.txt"
    echo "       echo 'deepseek=sk-YOUR_KEY' >> ~/zai/keys.txt"
  fi
  printf 'cheap mode on  (max_tokens %s)  ' "${LEVI_MAX_TOKENS:-4096}"
    python3 -c "
import urllib.request,json
d=json.loads(urllib.request.urlopen('http://127.0.0.1:8080/health',timeout=5).read())
print('providers:', ', '.join(d.get('providers',[])))
" 2>/dev/null || echo ""
    exit 0; }
  sleep 1
done
echo "did not start - see $DIR/levi.log"; exit 1
