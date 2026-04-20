#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$SCRIPT_DIR"

if [ ! -d "Leaflet.app" ]; then
  "$SCRIPT_DIR/scripts/package_app.sh"
fi

exec open "$SCRIPT_DIR/Leaflet.app"
