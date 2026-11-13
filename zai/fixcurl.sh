#!/bin/sh
# Repair a broken Termux curl / libcurl (SSL symbol errors) after a reinstall.
# Needs only pkg - no curl, no download.
echo "==> pkg update"
pkg update -y || { echo "!! pkg update failed - try: termux-change-repo"; exit 1; }
echo "==> pkg upgrade (brings openssl in line with libcurl)"
pkg upgrade -y
echo "==> reinstalling the two packages that disagree"
pkg install -y openssl libcurl
pkg reinstall -y openssl libcurl 2>/dev/null || true
echo
if curl --version >/dev/null 2>&1; then
  echo "OK: $(curl --version | head -1)"
else
  echo "still broken. next steps:"
  echo "  1) termux-change-repo   -> pick a different mirror, then run pkg upgrade -y"
  echo "  2) if that fails, reinstall Termux from F-Droid (NOT the Play Store)"
fi
