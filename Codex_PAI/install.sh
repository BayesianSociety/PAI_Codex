#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HOME/.local/bin/codex-pai"

mkdir -p "$HOME/.local/bin"
ln -sf "$ROOT_DIR/bin/codex-pai" "$TARGET"

echo "Installed: $TARGET -> $ROOT_DIR/bin/codex-pai"
echo "Ensure $HOME/.local/bin is in PATH."
echo "If Codex_PAI is not adjacent to your PAI root, set:"
echo "  export PAI_ROOT=/path/to/.claude"
