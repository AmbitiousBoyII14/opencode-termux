#!/bin/sh
# Levi setup for Termux - one command.
#   curl -fsSL https://raw.githubusercontent.com/AmbitiousBoyII14/opencode-termux/main/zai/install.sh | sh
set -e
RAW="https://raw.githubusercontent.com/AmbitiousBoyII14/opencode-termux/main/zai"
DIR="$HOME/zai"; OCDIR="$HOME/.config/opencode"

echo "==> python"
command -v python3 >/dev/null 2>&1 || { echo "    installing"; pkg install -y python >/dev/null 2>&1 || { echo "    !! pkg install python"; exit 1; }; }

echo "==> files -> $DIR"
mkdir -p "$DIR"
for f in levi-proxy.py levi-system-prompt.md; do
  curl -fsSL -o "$DIR/$f" "$RAW/$f"; echo "    $f"
done

echo "==> keys"
if [ ! -s "$DIR/keys.txt" ]; then
  # No keys are shipped in this script. Get your own:
  #   nvidia   https://build.nvidia.com          (free, SMS verify)
  #   deepseek https://platform.deepseek.com     ($2 min)
  echo "    !! no ~/zai/keys.txt found"
  echo "    Create it with one provider per line, e.g.:"
  echo "      echo 'nvidia=nvapi-YOUR_KEY' >> ~/zai/keys.txt"
  echo "      echo 'deepseek=sk-YOUR_KEY'  >> ~/zai/keys.txt"
  echo "    Then run this installer again."
else
  echo "    keys.txt kept"
fi
chmod 600 "$DIR/keys.txt"

echo "==> opencode config"
mkdir -p "$OCDIR"
[ -f "$OCDIR/opencode.json" ] && cp "$OCDIR/opencode.json" "$OCDIR/opencode.json.bak.$(date +%s)" && echo "    backed up"
cat > "$OCDIR/opencode.json" <<'JSON'
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "levi": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Levi",
      "options": { "baseURL": "http://127.0.0.1:8080/v1", "apiKey": "unused" },
      "models": {
        "glm-4.7-flash": {
          "name": "Levi (Nemotron)",
          "limit": { "context": 131072, "output": 8192 }
        }
      }
    }
  },
  "model": "levi/glm-4.7-flash"
}
JSON
echo "    $OCDIR/opencode.json"

echo "==> autostart"
curl -fsSL -o "$DIR/start.sh" "$RAW/start.sh" && chmod +x "$DIR/start.sh"
curl -fsSL -o "$DIR/boot.sh" "$RAW/boot.sh" && chmod +x "$DIR/boot.sh"
mkdir -p "$HOME/.termux/boot" && cp "$DIR/boot.sh" "$HOME/.termux/boot/levi-proxy" && chmod +x "$HOME/.termux/boot/levi-proxy"
if ! grep -q "zai/start.sh" "$HOME/.bashrc" 2>/dev/null; then
  printf '\n# Levi proxy\n[ -x "$HOME/zai/start.sh" ] && "$HOME/zai/start.sh" >/dev/null 2>&1\n' >> "$HOME/.bashrc"
fi
echo "    boot hook + .bashrc hook installed"

echo "==> starting proxy"
pkill -f levi-proxy.py 2>/dev/null || true
pkill -f zai-proxy.py 2>/dev/null || true
sleep 1
cd "$DIR"
nohup python3 levi-proxy.py > "$DIR/levi.log" 2>&1 &
for i in 1 2 3 4 5 6 7 8 9 10; do
  curl -fsS -m 5 http://127.0.0.1:8080/health >/dev/null 2>&1 && break
  sleep 2
done
if ! curl -fsS -m 5 http://127.0.0.1:8080/health >/dev/null 2>&1; then
  echo "    !! proxy failed:"; tail -20 "$DIR/levi.log"; exit 1
fi
echo "    $(curl -fsS -m 5 http://127.0.0.1:8080/health)"

echo "==> test"
R=$(curl -fsS -m 90 http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"glm-4.7-flash","messages":[{"role":"user","content":"say ready"}],"max_tokens":60}' \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['choices'][0]['message']['content'])" 2>/dev/null) || R=""

if [ -n "$R" ]; then
  echo
  echo "==================================================="
  echo " WORKING:"
  echo "   $R"
  echo "==================================================="
  echo
  echo " open opencode - Levi is already selected."
  echo " restart proxy: ~/zai/start.sh   (or just open a new Termux shell)"
else
  echo "    !! no reply"; tail -20 "$DIR/levi.log"; exit 1
fi
