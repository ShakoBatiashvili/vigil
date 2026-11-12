#!/bin/bash
# Installs dist/Vigil.app into ~/Applications. No sudo, nothing outside your home folder.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="dist/Vigil.app"
DEST="$HOME/Applications/Vigil.app"

[ -d "$SRC" ] || { echo "Build first: scripts/build-app.sh"; exit 1; }

# Quit a running copy so the new build replaces it cleanly.
if pgrep -x Vigil >/dev/null 2>&1; then
  echo "==> Quitting the running Vigil"
  osascript -e 'tell application "Vigil" to quit' >/dev/null 2>&1 || pkill -x Vigil || true
  sleep 1
fi

mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"
codesign --verify --strict "$DEST"
echo "Installed $DEST"
echo
echo "Open it:        open \"$DEST\""
echo "Command line:   $DEST/Contents/Helpers/vigil help"
echo "Put it on PATH: ln -s \"$DEST/Contents/Helpers/vigil\" ~/bin/vigil   (or any folder on your PATH)"
