#!/bin/zsh
set -euo pipefail

cd "${0:A:h}"

APP_NAME="Claude Notifier Manager"
EXECUTABLE="ClaudeNotifierManager"
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

# The notifier scripts ship inside the bundle so Settings can install one. They
# must be in place before signing — the signature seals Resources, and adding
# files afterwards invalidates it.
cp ../notify-telegram.sh ../notify-pushover.sh "${BUNDLE}/Contents/Resources/"

# Committed alongside the sources, so building needs no icon tooling. Run
# ./make-icon.swift to redraw it.
cp AppIcon.icns "${BUNDLE}/Contents/Resources/"

# Ad-hoc signature. Required to execute on Apple Silicon, and it is embedded in
# the Mach-O itself, so it survives being committed to and checked out of git.
codesign --force --sign - "$BUNDLE"

echo "Built ./${BUNDLE}"
echo "Run ./install.sh to copy it into ~/Applications."
