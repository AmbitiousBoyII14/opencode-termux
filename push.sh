#!/usr/bin/env bash
# Creates the GitHub repo and pushes this fork.
#
#   ./push.sh <your-github-username> [repo-name]
#
# Needs a GitHub token with `repo` (classic) or `Contents: read/write` +
# `Workflows: read/write` (fine-grained) — the workflow file requires the
# latter permission, which is why a plain `gh repo create` sometimes 403s.
#
#   export GITHUB_TOKEN=ghp_...
#   ./push.sh DioNanos opencode-termux
set -euo pipefail

USER="${1:-}"
NAME="${2:-opencode-termux}"
TOKEN="${GITHUB_TOKEN:-}"

[ -n "$USER" ] || { echo "usage: ./push.sh <github-username> [repo-name]" >&2; exit 1; }
[ -n "$TOKEN" ] || { echo "set GITHUB_TOKEN first (needs repo + workflow permissions)" >&2; exit 1; }

command -v git >/dev/null || { echo "git missing" >&2; exit 1; }
command -v curl >/dev/null || { echo "curl missing" >&2; exit 1; }

SLUG="$USER/$NAME"
API="https://api.github.com/repos/$SLUG"

echo "==> checking $SLUG"
if curl -sf -H "Authorization: Bearer $TOKEN" "$API" >/dev/null 2>&1; then
  echo "    repo exists, pushing into it"
else
  echo "    creating $SLUG"
  curl -sf -X POST https://api.github.com/user/repos \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -d "{\"name\":\"$NAME\",\"description\":\"Patched opencode for Termux (aarch64) — custom endpoint /connect only\",\"private\":false}" \
    >/dev/null || { echo "failed to create repo — check the token's scopes" >&2; exit 1; }
fi

# stamp the real slug into the installer and README before pushing
python3 - "$SLUG" <<'PY'
import pathlib, sys
slug = sys.argv[1]
for path in ("termux/install.sh", "README.md", "termux/install-opencode.sh"):
    p = pathlib.Path(path)
    if not p.exists():
        continue
    p.write_text(p.read_text().replace("__REPO__", slug))
    print(f"    stamped {path} -> {slug}")
PY

# workflow files need the `workflow` scope; use a token-authenticated remote
REMOTE="https://x-access-token:${TOKEN}@github.com/${SLUG}.git"

cd "$(dirname "$0")"

if [ ! -d .git ]; then
  git init -q
  git branch -M main
fi

git add -A
git -c user.name="opencode-termux" -c user.email="noreply@github.com" \
  commit -q -m "opencode for Termux: custom-endpoint /connect only" || echo "    (nothing new to commit)"

git remote remove origin 2>/dev/null || true
git remote add origin "$REMOTE"
git push -q -u origin main

# don't leave the token sitting in .git/config
git remote set-url origin "https://github.com/${SLUG}.git"

echo
echo "==> pushed: https://github.com/${SLUG}"
echo
echo "Next:"
echo "  1. Actions tab -> 'build-termux' -> Run workflow   (~15 min)"
echo "  2. when the artifact exists, tag a release:"
echo "       git tag v1.0.0 && git push origin v1.0.0"
echo "  3. on your phone:"
echo "       pkg install glibc-repo && pkg update && pkg install glibc glibc-runner"
echo "       curl -fsSL https://raw.githubusercontent.com/${SLUG}/main/termux/install.sh | bash"
