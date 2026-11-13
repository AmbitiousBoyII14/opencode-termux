#!/bin/sh
# Register BOTH backends as separate models in opencode so the picker is honest.
#   curl -fsSL .../zai/install-models.sh | sh
set -e
OCDIR="$HOME/.config/opencode"
mkdir -p "$OCDIR"
[ -f "$OCDIR/opencode.json" ] && cp "$OCDIR/opencode.json" "$OCDIR/opencode.json.bak.$(date +%s)" && echo "   backed up opencode.json"

cat > "$OCDIR/opencode.json" <<'JSON'
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "levi": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Levi",
      "options": { "baseURL": "http://127.0.0.1:8080/v1", "apiKey": "unused" },
      "models": {
        "deepseek-flash": {
          "name": "Levi - DeepSeek (paid, $0.15/M in)",
          "limit": { "context": 131072, "output": 8192 }
        },
        "nemotron-ultra": {
          "name": "Levi - Nemotron 550B (free)",
          "limit": { "context": 131072, "output": 8192 }
        }
      }
    }
  },
  "model": "levi/deepseek-flash"
}
JSON
echo "   wrote $OCDIR/opencode.json"
echo
echo "   models registered:"
echo "     levi/deepseek-flash   -> DeepSeek V4.1-Flash  (paid, the good one)"
echo "     levi/nemotron-ultra   -> Nemotron 550B        (free)"
echo
echo "   The proxy now ROUTES on the model you pick, instead of silently"
echo "   overriding it. Pick with /models inside opencode (ctrl+x then m)."
