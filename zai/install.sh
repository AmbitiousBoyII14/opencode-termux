#!/bin/sh
# Levi setup for Termux. One command, nothing to remember.
#
#   curl -fsSL https://raw.githubusercontent.com/AmbitiousBoyII14/opencode-termux/main/zai/install.sh | sh
#
# What it does:
#   1. puts the proxy + prompt + key in ~/zai
#   2. writes opencode's config to point at the proxy
#   3. starts the proxy in the background
#   4. tests it and prints the reply
#
# Safe to re-run.

set -e

RAW="https://raw.githubusercontent.com/AmbitiousBoyII14/opencode-termux/main/zai"
DIR="$HOME/zai"
OCDIR="$HOME/.config/opencode"

echo "==> checking python"
if ! command -v python3 >/dev/null 2>&1; then
  echo "    python3 missing, installing"
  pkg install -y python >/dev/null 2>&1 || {
    echo "    !! couldn't install python. run: pkg install python"; exit 1; }
fi
python3 -c "import sys; sys.exit(0 if sys.version_info>=(3,8) else 1)" || {
  echo "    !! need python 3.8+"; exit 1; }

echo "==> installing files to $DIR"
mkdir -p "$DIR"
for f in zai-proxy.py levi-system-prompt.md; do
  curl -fsSL -o "$DIR/$f" "$RAW/$f"
  echo "    $f"
done

if [ ! -s "$DIR/zai-key.txt" ]; then
  printf '%s\n' "ccf5870abae14fca9207070761af063e.FCXeTBk3a9O1ra3R" > "$DIR/zai-key.txt"
  echo "    zai-key.txt (written)"
else
  echo "    zai-key.txt (kept existing)"
fi
chmod 600 "$DIR/zai-key.txt"

echo "==> writing opencode config"
mkdir -p "$OCDIR"
if [ -f "$OCDIR/opencode.json" ]; then
  cp "$OCDIR/opencode.json" "$OCDIR/opencode.json.bak.$(date +%s)"
  echo "    backed up existing opencode.json"
fi
cat > "$OCDIR/opencode.json" <<'JSON'
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "levi": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Levi",
      "options": {
        "baseURL": "http://127.0.0.1:8080/v1",
        "apiKey": "unused"
      },
      "models": {
        "glm-4.7-flash": {
          "name": "GLM-4.7-Flash",
          "limit": { "context": 131072, "output": 8192 }
        }
      }
    }
  },
  "model": "levi/glm-4.7-flash"
}
JSON
echo "    $OCDIR/opencode.json"

echo "==> starting proxy"
pkill -f zai-proxy.py 2>/dev/null || true
sleep 1
cd "$DIR"
nohup python3 zai-proxy.py > "$DIR/zai.log" 2>&1 &
sleep 3

for i in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS -m 5 http://127.0.0.1:8080/health >/dev/null 2>&1; then break; fi
  sleep 2
done

if ! curl -fsS -m 5 http://127.0.0.1:8080/health >/dev/null 2>&1; then
  echo "    !! proxy didn't start. log:"
  tail -20 "$DIR/zai.log"
  exit 1
fi

echo "==> health"
curl -fsS -m 10 http://127.0.0.1:8080/health
echo

echo "==> test (may take up to 60s on the free tier)"
REPLY=$(curl -fsS -m 180 http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"glm-4.7-flash","messages":[{"role":"user","content":"say ready"}],"max_tokens":60}' \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['choices'][0]['message']['content'])" 2>/dev/null) || REPLY=""

if [ -n "$REPLY" ]; then
  echo
  echo "==================================================="
  echo " WORKING. model said:"
  echo "   $REPLY"
  echo "==================================================="
  echo
  echo " open opencode. Levi is already selected."
  echo
  echo " proxy is running in the background."
  echo " if it stops:   cd ~/zai && nohup python3 zai-proxy.py > zai.log 2>&1 &"
  echo " check health:  curl -s localhost:8080/health"
else
  echo "    !! no reply. last log lines:"
  tail -20 "$DIR/zai.log"
  echo
  echo "    the free tier is busy sometimes - try: curl -s localhost:8080/health"
  exit 1
fi
