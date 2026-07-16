#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-}"
REPOSITORY="fslot2601-source/workbench"
WORK_DIR="$ROOT/.build/appcast-feed"
OUTPUT="${APPCAST_OUTPUT:-$ROOT/appcast.xml}"

if [[ -z "$VERSION" ]]; then
    echo "usage: $0 VERSION [RELEASE_NOTES]" >&2
    exit 64
fi

NOTES="${2:-$ROOT/docs/RELEASE_NOTES_${VERSION}.md}"
if [[ ! -f "$NOTES" ]]; then
    echo "Release notes not found: $NOTES" >&2
    exit 66
fi

shopt -s nullglob
archives=("$ROOT/dist/Workbench-${VERSION}-"*.zip)
shopt -u nullglob
if (( ${#archives[@]} != 1 )); then
    echo "Expected exactly one ZIP for Workbench ${VERSION} in dist/." >&2
    exit 66
fi

GENERATOR="${SPARKLE_GENERATE_APPCAST:-}"
if [[ -z "$GENERATOR" ]]; then
    GENERATOR="$(find "$ROOT/.build" -type f -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast' -print -quit 2>/dev/null || true)"
fi
if [[ -z "$GENERATOR" || ! -x "$GENERATOR" ]]; then
    echo "Sparkle generate_appcast was not found. Resolve Swift packages with Xcode first." >&2
    exit 69
fi

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cp "${archives[0]}" "$WORK_DIR/"
archive_name="$(basename "${archives[0]}" .zip)"
cp "$NOTES" "$WORK_DIR/${archive_name}.md"
if [[ -f "$OUTPUT" ]]; then
    cp "$OUTPUT" "$WORK_DIR/appcast.xml"
fi

"$GENERATOR" \
    --account workbench \
    --download-url-prefix "https://github.com/${REPOSITORY}/releases/download/v${VERSION}/" \
    --link "https://github.com/${REPOSITORY}/releases/latest" \
    --embed-release-notes \
    --maximum-versions 3 \
    --maximum-deltas 0 \
    -o "$WORK_DIR/appcast.xml" \
    "$WORK_DIR"

xmllint --noout "$WORK_DIR/appcast.xml"
mkdir -p "$(dirname "$OUTPUT")"
cp "$WORK_DIR/appcast.xml" "$OUTPUT"

echo "Updated $OUTPUT for Workbench $VERSION."
echo "Commit and push appcast.xml only after the matching GitHub Release assets are public."
