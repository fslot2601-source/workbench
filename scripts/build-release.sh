#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="$ROOT/.build/release"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
ARCHIVE="$BUILD_ROOT/SkillLens.xcarchive"
STAGE="$BUILD_ROOT/stage"
DIST="$ROOT/dist"

rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT" "$STAGE" "$DIST"

if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate --spec "$ROOT/project.yml" --project "$ROOT"
fi

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

SOURCE_APP="$ARCHIVE/Products/Applications/SkillLens.app"
test -d "$SOURCE_APP"
cp -R "$SOURCE_APP" "$STAGE/Skill Lens.app"
APP="$STAGE/Skill Lens.app"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
BASE_NAME="Skill-Lens-${VERSION}-${BUILD}"

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    codesign --force --deep --strict --options runtime --timestamp \
        --sign "$DEVELOPER_ID_APPLICATION" "$APP"
    codesign --verify --deep --strict --verbose=2 "$APP"
fi

ZIP="$DIST/${BASE_NAME}.zip"
DMG="$DIST/${BASE_NAME}.dmg"
CHECKSUMS="$DIST/${BASE_NAME}-SHA256SUMS.txt"
rm -f "$ZIP" "$DMG" "$CHECKSUMS"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -fs HFS+ -volname "Skill Lens ${VERSION}" -srcfolder "$STAGE" "$DMG"

if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
    if [[ -z "${DEVELOPER_ID_APPLICATION:-}" ]]; then
        echo "NOTARYTOOL_PROFILE requires DEVELOPER_ID_APPLICATION." >&2
        exit 1
    fi
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
fi

(cd "$DIST" && shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")" > "$(basename "$CHECKSUMS")")

EXPECT_SIGNED="$([[ -n "${DEVELOPER_ID_APPLICATION:-}" ]] && echo 1 || echo 0)" \
    "$ROOT/scripts/verify-release.sh" "$APP" "$ZIP" "$DMG" "$CHECKSUMS"

echo "Release artifacts:"
echo "  $ZIP"
echo "  $DMG"
echo "  $CHECKSUMS"
