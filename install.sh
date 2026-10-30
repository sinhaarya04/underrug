#!/bin/sh
# Install Underrug: download the latest release into /Applications and open it.
#   curl -fsSL https://raw.githubusercontent.com/sinhaarya04/underrug/main/install.sh | sh
#
# curl, unlike a browser, doesn't mark what it downloads as quarantined, so macOS opens the app
# without the "can't check it for malicious software" prompt. UNDERRUG_DIR picks another folder.
set -e

DEST="${UNDERRUG_DIR:-/Applications}"
URL="https://github.com/sinhaarya04/underrug/releases/latest/download/Underrug.zip"

if [ "$(uname)" != "Darwin" ]; then echo "Underrug is a macOS app." >&2; exit 1; fi
# /Applications needs an admin account; fall back to the user's own Applications folder
if [ ! -w "$DEST" ]; then DEST="$HOME/Applications"; fi
mkdir -p "$DEST"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Downloading Underrug…"
curl -fsSL "$URL" -o "$TMP/Underrug.zip"
ditto -x -k "$TMP/Underrug.zip" "$TMP"
[ -d "$TMP/Underrug.app" ] || { echo "The download didn't contain Underrug.app." >&2; exit 1; }

# replace an older copy, quitting it first
pkill -x Underrug 2>/dev/null || true
rm -rf "$DEST/Underrug.app"
ditto "$TMP/Underrug.app" "$DEST/Underrug.app"
xattr -dr com.apple.quarantine "$DEST/Underrug.app" 2>/dev/null || true

echo "Installed $DEST/Underrug.app"
[ -n "$UNDERRUG_NO_OPEN" ] || open "$DEST/Underrug.app"
