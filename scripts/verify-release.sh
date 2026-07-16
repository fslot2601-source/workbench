#!/bin/bash
set -Eeuo pipefail

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
DMG_MOUNT="$TEMP_DIR/dmg-mount"
DMG_ATTACHED=0

cleanup_mount() {
    if [[ "$DMG_ATTACHED" = "1" ]]; then
        hdiutil detach "$DMG_MOUNT" >/dev/null 2>&1 || true
    fi
}
trap cleanup_mount ERR INT TERM

test -d "$APP"
test -f "$ZIP"
test -f "$DMG"
test -f "$CHECKSUMS"

validate_app() {
    local candidate="$1"
    local expected_version="$2"
    local expected_build="$3"
    local plist="$candidate/Contents/Info.plist"
    local privacy="$candidate/Contents/Resources/PrivacyInfo.xcprivacy"
    local executable="$candidate/Contents/MacOS/Workbench"
    local sparkle="$candidate/Contents/Frameworks/Sparkle.framework"

    test -d "$candidate"
    plutil -lint "$plist" "$privacy"
    test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" = "dev.skilllens.app"
    test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" = "$expected_version"
    test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")" = "$expected_build"
    test -x "$executable"
    test -d "$sparkle"
    test "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$plist")" = "IRigQ31Wujzi5fOaTekPlKJaom/JvrYfuSmkgjeiiOo="
    test "$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$plist")" = "https://raw.githubusercontent.com/fslot2601-source/workbench/main/appcast.xml"

    local archs
    archs="$(lipo -archs "$executable")"
    echo "$archs" | grep -q arm64
    echo "$archs" | grep -q x86_64
}

compare_app() {
    local expected="$1"
    local candidate="$2"
    local changes

    changes="$(rsync -rnic --delete --links --itemize-changes "$expected/" "$candidate/")"
    if [[ -n "$changes" ]]; then
        echo "Packaged application differs from the verified build:" >&2
        echo "$changes" >&2
        exit 65
    fi
}

PLIST="$APP/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
validate_app "$APP" "$VERSION" "$BUILD"

ditto -x -k "$ZIP" "$TEMP_DIR/zip-check"
ZIP_APP="$TEMP_DIR/zip-check/Workbench.app"
validate_app "$ZIP_APP" "$VERSION" "$BUILD"
compare_app "$APP" "$ZIP_APP"

hdiutil verify "$DMG"
mkdir -p "$DMG_MOUNT"
hdiutil attach -nobrowse -readonly -mountpoint "$DMG_MOUNT" "$DMG" >/dev/null
DMG_ATTACHED=1
DMG_APP="$DMG_MOUNT/Workbench.app"
validate_app "$DMG_APP" "$VERSION" "$BUILD"
test -L "$DMG_MOUNT/Applications"
test "$(readlink "$DMG_MOUNT/Applications")" = "/Applications"
compare_app "$APP" "$DMG_APP"
hdiutil detach "$DMG_MOUNT" >/dev/null
DMG_ATTACHED=0

(cd "$(dirname "$CHECKSUMS")" && shasum -a 256 -c "$(basename "$CHECKSUMS")")

SIGNATURE_INFO="$(codesign -d --verbose=4 "$APP" 2>&1 || true)"
if echo "$SIGNATURE_INFO" | grep -q 'Authority=Developer ID Application'; then
    codesign --verify --deep --strict --verbose=2 "$APP"
    codesign -d --verbose=4 "$APP" 2>&1 | grep -q 'Authority=Developer ID Application'
    codesign --verify --strict --verbose=2 "$DMG"
    codesign -d --verbose=4 "$DMG" 2>&1 | grep -q 'Authority=Developer ID Application'
    xcrun stapler validate "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
else
    if codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then
        echo "Artifacts signed without Developer ID Application are not accepted." >&2
        exit 65
    fi
    if [[ "${ALLOW_UNSIGNED:-0}" != "1" ]]; then
        echo "Unsigned artifacts require ALLOW_UNSIGNED=1 and are never valid public releases." >&2
        exit 65
    fi
    echo "Unsigned community artifact verified. If published, label it as unsigned and not notarized."
fi
