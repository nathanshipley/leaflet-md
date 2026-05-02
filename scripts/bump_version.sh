#!/bin/bash
#
# bump_version.sh — Set MARKETING_VERSION in Leaflet.xcodeproj so the
# About panel and Info.plist match the beta we're cutting. Run this
# BEFORE xcodebuild Release so the new build picks up the change.
#
# Usage:
#   scripts/bump_version.sh <version>
#
# Example:
#   scripts/bump_version.sh 0.1.0-beta.8
#
# This rewrites both the Debug and Release MARKETING_VERSION entries
# in Leaflet.xcodeproj/project.pbxproj.

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <version>"
    echo "example: $0 0.1.0-beta.8"
    exit 64
fi

VERSION="$1"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PBXPROJ="$REPO_ROOT/Leaflet.xcodeproj/project.pbxproj"
INFO_PLIST="$REPO_ROOT/Leaflet/Info.plist"

if [[ ! -f "$PBXPROJ" ]]; then
    echo "error: project file not found at $PBXPROJ" >&2
    exit 1
fi

if [[ ! -f "$INFO_PLIST" ]]; then
    echo "error: Info.plist not found at $INFO_PLIST" >&2
    exit 1
fi

# Validate format loosely: digits, dots, optional -beta.N / -rc.N suffix.
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-(beta|rc|alpha)\.[0-9]+)?$ ]]; then
    echo "error: version '$VERSION' does not look like X.Y.Z[-beta.N]" >&2
    exit 1
fi

# pbxproj: rewrite both Debug and Release MARKETING_VERSION entries.
sed -i '' -E "s/(MARKETING_VERSION = )[^;]+;/\1${VERSION};/g" "$PBXPROJ"

# Info.plist: rewrite CFBundleShortVersionString. The Info.plist hardcodes
# the literal string rather than referencing $(MARKETING_VERSION), so
# Xcode's build-setting substitution doesn't reach it. Use PlistBuddy
# (preserves XML formatting) instead of sed across XML tags.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$INFO_PLIST"

echo "==> set MARKETING_VERSION to ${VERSION} in:"
grep -n "MARKETING_VERSION" "$PBXPROJ"
echo "==> set CFBundleShortVersionString in $INFO_PLIST to:"
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST"
