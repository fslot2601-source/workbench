#!/bin/bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
    echo "usage: verify-release.sh APP ZIP DMG CHECKSUMS" >&2
    exit 64
fi

APP="$1"
ZIP="$2"
DMG="$3"
CHECKSUMS="$4"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

test -d "$APP"
test -f "$ZIP"
test -f "$DMG"
test -f "$CHECKSUMS"

PLIST="$APP/Contents/Info.plist"
PRIVACY="$APP/Contents/Resources/PrivacyInfo.xcprivacy"
EXECUTABLE="$APP/Contents/MacOS/SkillLens"

plutil -lint "$PLIST" "$PRIVACY"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")" = "dev.skilllens.app"
test -n "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
test -x "$EXECUTABLE"

ARCHS="$(lipo -archs "$EXECUTABLE")"
echo "$ARCHS" | grep -q arm64
echo "$ARCHS" | grep -q x86_64

ditto -x -k "$ZIP" "$TEMP_DIR/zip-check"
hdiutil verify "$DMG"
(cd "$(dirname "$CHECKSUMS")" && shasum -a 256 -c "$(basename "$CHECKSUMS")")

if [[ "${EXPECT_SIGNED:-0}" = "1" ]]; then
    codesign --verify --deep --strict --verbose=2 "$APP"
    codesign -d --verbose=4 "$APP" 2>&1 | grep -q 'Authority=Developer ID Application'
else
    echo "Unsigned local artifact verified. Do not publish it as notarized software."
fi
