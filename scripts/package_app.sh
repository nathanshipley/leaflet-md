#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_DIR"

CONFIGURATION="${CONFIGURATION:-debug}"
case "$CONFIGURATION" in
  debug|release) ;;
  *)
    echo "Unsupported CONFIGURATION: $CONFIGURATION" >&2
    echo "Expected 'debug' or 'release'." >&2
    exit 1
    ;;
esac

BUILD_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
rm -rf "$BUILD_DIR/MarkdownViewer_MarkdownViewerCore.bundle"
rm -rf "$BUILD_DIR/MarkdownViewer_MarkdownViewer.bundle"

swift build -c "$CONFIGURATION"

APP_EXECUTABLE_NAME="Leaflet"
CORE_RESOURCE_BUNDLE_NAME="MarkdownViewer_MarkdownViewerCore.bundle"
APP_RESOURCE_BUNDLE_NAME="MarkdownViewer_MarkdownViewer.bundle"
APP_BUNDLE="${APP_BUNDLE:-$REPO_DIR/Leaflet.app}"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

if [[ -z "$APP_BUNDLE" || "$APP_BUNDLE" == "/" || "$APP_BUNDLE" != *.app ]]; then
  echo "Refusing to package to unsafe APP_BUNDLE path: $APP_BUNDLE" >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

/usr/bin/ditto --noextattr --noqtn "$REPO_DIR/Support/MarkdownViewer-Info.plist" "$CONTENTS_DIR/Info.plist"
/usr/bin/ditto --noextattr --noqtn "$BUILD_DIR/MarkdownViewer" "$MACOS_DIR/$APP_EXECUTABLE_NAME"
chmod +x "$MACOS_DIR/$APP_EXECUTABLE_NAME"

/usr/bin/ditto --noextattr --noqtn "$REPO_DIR/Support/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
/usr/bin/ditto --noextattr --noqtn "$REPO_DIR/Support/Assets.car" "$RESOURCES_DIR/Assets.car"

if [ -d "$BUILD_DIR/$CORE_RESOURCE_BUNDLE_NAME" ]; then
  /usr/bin/ditto --noextattr --noqtn "$BUILD_DIR/$CORE_RESOURCE_BUNDLE_NAME" "$RESOURCES_DIR/$CORE_RESOURCE_BUNDLE_NAME"
fi

if [ -d "$BUILD_DIR/$APP_RESOURCE_BUNDLE_NAME" ]; then
  /usr/bin/ditto --noextattr --noqtn "$BUILD_DIR/$APP_RESOURCE_BUNDLE_NAME" "$RESOURCES_DIR/$APP_RESOURCE_BUNDLE_NAME"
fi

/usr/bin/xattr -cr "$APP_BUNDLE"

/usr/bin/codesign --force --sign - "$MACOS_DIR/$APP_EXECUTABLE_NAME"
/usr/bin/codesign --force --sign - "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict --verbose=4 "$APP_BUNDLE"

touch "$APP_BUNDLE"

echo "Packaged app at: $APP_BUNDLE"
