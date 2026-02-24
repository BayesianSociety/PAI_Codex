#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

OUT_FILE="${1:-$STATE_DIR/context-cache.md}"

{
  echo "# Codex_PAI Session Context"
  echo
  echo "Generated: $(now_iso)"
  echo "Workspace: $(pwd)"
  echo ""
  echo "## Core Context Files"

  mapfile -t files < <(json_array_lines '.paths.context_files')
  for rel in "${files[@]}"; do
    full="$PAI_ROOT_DIR/$rel"
    echo ""
    echo "### $rel"
    if [[ -f "$full" ]]; then
      # Rewrite legacy install-root paths in injected context to active PAI_ROOT_DIR.
      sed -n '1,220p' "$full" \
        | sed "s#~/.claude#${PAI_ROOT_DIR}#g" \
        | sed "s#/home/postnl/Personal_AI_Infrastructure/Releases/v3.0/.claude#${PAI_ROOT_DIR}#g"
    else
      echo "(missing: $full)"
    fi
  done
} > "$OUT_FILE"

echo "$OUT_FILE"
