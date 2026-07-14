#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="$ROOT/.build/release"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
ARCHIVE="$BUILD_ROOT/SkillLens.xcarchive"
STAGE="$BUILD_ROOT/stage"
DIST="$ROOT/dist"
PACKAGE_DIR="$BUILD_ROOT/artifacts"
SIGNING_IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
NOTARY_PROFILE="${NOTARYTOOL_PROFILE:-}"

if [[ -n "$SIGNING_IDENTITY" && -z "$NOTARY_PROFILE" ]] || \
   [[ -z "$SIGNING_IDENTITY" && -n "$NOTARY_PROFILE" ]]; then
    echo "Public release mode requires both DEVELOPER_ID_APPLICATION and NOTARYTOOL_PROFILE." >&2
    exit 64
fi

rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT" "$STAGE" "$PACKAGE_DIR" "$DIST"

shopt -s nullglob
existing_artifacts=("$DIST"/Workbench-* "$DIST"/Skill-Lens-*)
shopt -u nullglob
if (( ${#existing_artifacts[@]} > 0 )); then
    PREVIOUS_DIR="$DIST/archive/$(date -u +%Y%m%dT%H%M%SZ)-$$"
    mkdir -p "$PREVIOUS_DIR"
    for existing in "${existing_artifacts[@]}"; do
        mv "$existing" "$PREVIOUS_DIR/"
    done
fi

command -v xcodegen >/dev/null 2>&1 || {
    echo "xcodegen is required to build a release." >&2
    exit 69
}
xcodegen generate --spec "$ROOT/project.yml" --project "$ROOT"

xcodebuild \
    -project "$ROOT/SkillLens.xcodeproj" \
    -scheme SkillLens \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    -archivePath "$ARCHIVE" \
    CODE_SIGNING_ALLOWED=NO \
    SKIP_INSTALL=NO \
    clean archive

SOURCE_APP="$ARCHIVE/Products/Applications/Workbench.app"
test -d "$SOURCE_APP"
cp -R "$SOURCE_APP" "$STAGE/Workbench.app"
APP="$STAGE/Workbench.app"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
BASE_NAME="Workbench-${VERSION}-${BUILD}"
FINAL_ZIP="$DIST/${BASE_NAME}.zip"
FINAL_DMG="$DIST/${BASE_NAME}.dmg"
FINAL_CHECKSUMS="$DIST/${BASE_NAME}-SHA256SUMS.txt"

if [[ -n "$SIGNING_IDENTITY" ]]; then
    codesign --force --deep --strict --options runtime --timestamp \
        --sign "$SIGNING_IDENTITY" "$APP"
    codesign --verify --deep --strict --verbose=2 "$APP"
fi

ZIP="$PACKAGE_DIR/${BASE_NAME}.zip"
DMG="$PACKAGE_DIR/${BASE_NAME}.dmg"
CHECKSUMS="$PACKAGE_DIR/${BASE_NAME}-SHA256SUMS.txt"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -fs HFS+ -volname "Workbench ${VERSION}" -srcfolder "$STAGE" "$DMG"

if [[ -n "$SIGNING_IDENTITY" ]]; then
    codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG"
    codesign --verify --strict --verbose=2 "$DMG"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
fi

(cd "$PACKAGE_DIR" && shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")" > "$(basename "$CHECKSUMS")")

if [[ -n "$SIGNING_IDENTITY" ]]; then
    "$ROOT/scripts/verify-release.sh" "$APP" "$ZIP" "$DMG" "$CHECKSUMS"
else
    ALLOW_UNSIGNED=1 "$ROOT/scripts/verify-release.sh" "$APP" "$ZIP" "$DMG" "$CHECKSUMS"
fi

mv -f "$ZIP" "$FINAL_ZIP"
mv -f "$DMG" "$FINAL_DMG"
mv -f "$CHECKSUMS" "$FINAL_CHECKSUMS"

echo "Release artifacts:"
echo "  $FINAL_ZIP"
echo "  $FINAL_DMG"
echo "  $FINAL_CHECKSUMS"
