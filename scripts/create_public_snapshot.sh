#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEST="${1:-$REPO_DIR/release/Leaflet-public}"

if [[ -z "$DEST" || "$DEST" == "/" ]]; then
  echo "Refusing to create snapshot at unsafe path: $DEST" >&2
  exit 1
fi

rm -rf "$DEST"
mkdir -p "$DEST"

copy_item() {
  local source="$1"
  local target="$DEST/$source"
  mkdir -p "$(dirname "$target")"
  cp -R "$REPO_DIR/$source" "$target"
}

copy_item ".gitignore"
copy_item "Build Leaflet App.command"
copy_item "LICENSE"
copy_item "NOTICE"
copy_item "Package.resolved"
copy_item "Package.swift"
copy_item "README.md"
copy_item "Try Leaflet.command"

copy_item "Sources"
copy_item "Tests"
copy_item "scripts"
copy_item "tools"

mkdir -p "$DEST/Samples"
copy_item "Samples/second-window-demo.md"
copy_item "Samples/slack-export-kitchen-sink.md"
copy_item "Samples/slack-export-table-demo.md"
copy_item "Samples/slack-export-test.md"

mkdir -p "$DEST/Support"
copy_item "Support/AppIcon.icns"
copy_item "Support/Assets.car"
copy_item "Support/MarkdownViewer-Info.plist"

mkdir -p "$DEST/docs"
copy_item "docs/GITHUB_RELEASE_DRAFT.md"
copy_item "docs/ICON_PIPELINE.md"
copy_item "docs/RELEASE_TESTING.md"
copy_item "docs/THIRD_PARTY_NOTICES.md"

mkdir -p "$DEST/icon"
copy_item "icon/IconCompose_02.icon"
copy_item "icon/IconCompose_02-macOS-Default-1024x1024@1x.png"
copy_item "icon/Leaflet_AppIcon_44.png"
copy_item "icon/Logo_Horizontal_v3.png"
copy_item "icon/Leaflet_ReadmeLogo_320.png"

find "$DEST" -name ".DS_Store" -delete

(
  cd "$DEST"
  git init
  git add .
  git commit -m "Initial public beta release" >/dev/null
  git branch -M main
  git tag -a v0.1.0-beta.1 -m "Leaflet v0.1.0-beta.1"
)

echo "Clean public repo snapshot:"
echo "  $DEST"
