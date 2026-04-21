#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

VERSION="${1:-v0.1.0-beta.1}"
DISPLAY_VERSION="${VERSION#v}"
APP_NAME="Leaflet"
ARTIFACT_NAME="$APP_NAME-$VERSION-macOS-arm64"
RELEASE_DIR="$REPO_DIR/release"
STAGING_DIR="$RELEASE_DIR/staging/$ARTIFACT_NAME"
APP_BUNDLE="$STAGING_DIR/$APP_NAME.app"
ZIP_PATH="$RELEASE_DIR/$ARTIFACT_NAME.zip"
CHECKSUM_PATH="$ZIP_PATH.sha256"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "This beta release script currently builds the Apple Silicon artifact only." >&2
  echo "Run it on an Apple Silicon Mac or add a universal-build pipeline first." >&2
  exit 1
fi

rm -rf "$STAGING_DIR" "$ZIP_PATH" "$CHECKSUM_PATH"
mkdir -p "$STAGING_DIR"

CONFIGURATION=release APP_BUNDLE="$APP_BUNDLE" "$REPO_DIR/scripts/package_app.sh"

cp "$REPO_DIR/LICENSE" "$STAGING_DIR/LICENSE"
cp "$REPO_DIR/NOTICE" "$STAGING_DIR/NOTICE"
cp "$REPO_DIR/docs/THIRD_PARTY_NOTICES.md" "$STAGING_DIR/THIRD_PARTY_NOTICES.md"
cat > "$STAGING_DIR/README-FIRST.txt" <<EOF
Leaflet $DISPLAY_VERSION beta

This is an unsigned friends-and-family beta for Apple Silicon Macs running
macOS 13 or newer.

Install:
1. Move Leaflet.app to Applications.
2. Open it.
3. If macOS blocks the app because it is from an unidentified developer,
   Control-click Leaflet.app, choose Open, then choose Open again.
4. On Tahoe, if macOS says Leaflet is damaged and does not show Open Anyway,
   run this in Terminal after moving the app to Applications:
   xattr -dr com.apple.quarantine /Applications/Leaflet.app

Please test:
- opening Markdown files
- Preview and Code views
- Find with Command-F and Command-G
- Copy for Slack into Slack desktop and Slack in Chrome
- nested lists, code blocks, tables, bold, italic, strikethrough, and links

Send feedback with your macOS version, Mac chip, Slack version, and a screenshot
or sample Markdown for anything that breaks.
EOF

(
  cd "$RELEASE_DIR/staging"
  /usr/bin/zip -qry "$ZIP_PATH" "$ARTIFACT_NAME"
)

/usr/bin/shasum -a 256 "$ZIP_PATH" > "$CHECKSUM_PATH"

echo "Release artifact:"
echo "  $ZIP_PATH"
echo "Checksum:"
echo "  $CHECKSUM_PATH"
