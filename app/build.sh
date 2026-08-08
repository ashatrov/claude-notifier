#!/bin/zsh
set -euo pipefail

cd "${0:A:h}"

APP_NAME="Claude Notifyer Manager"
EXECUTABLE="ClaudeNotifyerManager"
BUNDLE="${APP_NAME}.app"

# Native build by default. Set ARCHS="arm64 x86_64" for a universal binary that
# also runs on Intel Macs — the bundle is committed to git, so that may matter.
ARCHS="${ARCHS:-arm64}"

ARCH_FLAGS=()
for arch in ${=ARCHS}; do
    ARCH_FLAGS+=(--arch "$arch")
done

echo "Building ${APP_NAME} (${ARCHS})..."
swift build -c release "${ARCH_FLAGS[@]}"

# Universal builds land somewhere different from single-arch ones, so ask
# SwiftPM for the path rather than hardcoding it.
BIN_PATH="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

rm -rf "$BUNDLE"
mkdir -p "${BUNDLE}/Contents/MacOS" "${BUNDLE}/Contents/Resources"

cp "${BIN_PATH}/${EXECUTABLE}" "${BUNDLE}/Contents/MacOS/${EXECUTABLE}"
cp Info.plist "${BUNDLE}/Contents/Info.plist"

# Ad-hoc signature. Required to execute on Apple Silicon, and it is embedded in
# the Mach-O itself, so it survives being committed to and checked out of git.
codesign --force --sign - "$BUNDLE"

echo "Built ./${BUNDLE}"
echo "Run ./install.sh to copy it into ~/Applications."
