#!/bin/zsh
set -euo pipefail

cd "${0:A:h}"

APP_NAME="Claude Notifyer Manager"
EXECUTABLE="ClaudeNotifyerManager"
BUNDLE="${APP_NAME}.app"
DEST="${HOME}/Applications"

if [[ ! -d "$BUNDLE" ]]; then
    echo "No ${BUNDLE} in $(pwd)." >&2
    echo "Run ./build.sh first, or check out the committed bundle." >&2
    exit 1
fi

# Quitting from the menu is what terminates caffeinate and clears the `enabled`
# flag, so refuse to replace the bundle out from under a running copy.
if pgrep -x "$EXECUTABLE" >/dev/null 2>&1; then
    echo "${APP_NAME} is running. Quit it from the menu bar, then run this again." >&2
    exit 1
fi

mkdir -p "$DEST"
rm -rf "${DEST}/${BUNDLE}"
# A copy, not a symlink: Spotlight does not index symlinked app bundles.
cp -R "$BUNDLE" "${DEST}/"

echo "Installed ${DEST}/${BUNDLE}"
echo "Launch it with: open \"${DEST}/${BUNDLE}\""
