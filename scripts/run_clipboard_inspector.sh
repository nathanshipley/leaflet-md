#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TOOL_DIR="$ROOT_DIR/tools/clipboard-inspector"
BIND_HOST="${CLIPBOARD_INSPECTOR_HOST:-127.0.0.1}"
PORT="${1:-8765}"

cd "$TOOL_DIR"

echo "Clipboard Inspector"
echo "Serving $TOOL_DIR"
echo "Open: http://$BIND_HOST:$PORT/"
echo

python3 -m http.server "$PORT" --bind "$BIND_HOST"
