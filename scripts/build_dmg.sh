#!/bin/bash
#
# build_dmg.sh — Wraps a stapled Leaflet.app in a signed, notarized,
# stapled .dmg ready for public distribution.
#
# Prerequisites:
#   - Leaflet.app already built, signed, notarized, and stapled by the
#     normal Xcode Release pipeline.
#   - Developer ID Application certificate available in the keychain.
#   - Notarization credentials stored under keychain profile "leaflet-notary"
#     (created with `xcrun notarytool store-credentials`).
#
# Usage:
#   scripts/build_dmg.sh <version>
#
# Example:
#   scripts/build_dmg.sh 0.1.0-beta.6
#
# Output:
#   .release/Leaflet-v<version>-macOS-universal.dmg (+ .sha256)

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <version>"
    echo "example: $0 0.1.0-beta.6"
    exit 64
fi

VERSION="$1"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${LEAFLET_APP_PATH:-$REPO_ROOT/release/Leaflet-public/.build/xcode/Build/Products/Release/Leaflet.app}"
RELEASE_DIR="${LEAFLET_RELEASE_DIR:-$REPO_ROOT/release/Leaflet-public/.release}"

CODESIGN_IDENTITY="${LEAFLET_CODESIGN_IDENTITY:-Developer ID Application: NATHAN BRITT SHIPLEY (53J4784RD9)}"
NOTARY_PROFILE="${LEAFLET_NOTARY_PROFILE:-leaflet-notary}"

DMG_NAME="Leaflet-v${VERSION}-macOS-universal.dmg"
VOLUME_NAME="Leaflet ${VERSION}"

if [[ ! -d "$APP_PATH" ]]; then
    echo "error: Leaflet.app not found at $APP_PATH" >&2
    echo "set LEAFLET_APP_PATH to override" >&2
    exit 1
fi

echo "==> verifying source app is stapled"
xcrun stapler validate "$APP_PATH"

mkdir -p "$RELEASE_DIR"

STAGE_DIR="$(mktemp -d -t leaflet-dmg-stage)"
BUILD_DIR="$(mktemp -d -t leaflet-dmg-build)"
trap 'rm -rf "$STAGE_DIR" "$BUILD_DIR"' EXIT

echo "==> staging $APP_PATH"
cp -R "$APP_PATH" "$STAGE_DIR/Leaflet.app"
ln -s /Applications "$STAGE_DIR/Applications"

DMG_PATH="$RELEASE_DIR/$DMG_NAME"
# Important: keep the temp dmg OUTSIDE the stage dir, otherwise hdiutil
# snapshots its own in-progress output back into the final image.
TMP_DMG="$BUILD_DIR/build.dmg"

# Remove any prior artifact so hdiutil doesn't refuse.
rm -f "$DMG_PATH"

echo "==> creating compressed dmg"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGE_DIR" \
    -ov \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$TMP_DMG"

mv "$TMP_DMG" "$DMG_PATH"

echo "==> signing dmg with $CODESIGN_IDENTITY"
codesign \
    --sign "$CODESIGN_IDENTITY" \
    --timestamp \
    --options runtime \
    "$DMG_PATH"

echo "==> verifying signature"
codesign --verify --verbose=2 "$DMG_PATH"

echo "==> submitting to apple notary service (this can take a few minutes)"
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "==> stapling notarization ticket"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

echo "==> running gatekeeper assessment"
spctl --assess --type install --verbose=4 "$DMG_PATH" 2>&1 || {
    echo "warning: spctl assessment failed; investigate before shipping" >&2
    exit 1
}

echo "==> writing sha-256"
( cd "$RELEASE_DIR" && shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256" )
cat "$DMG_PATH.sha256"

echo
echo "done: $DMG_PATH"
