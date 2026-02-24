#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

SESSION_ID="$1"
WORKSPACE_DIR="$2"

skills_count=$(find "$PAI_ROOT_DIR/skills" -maxdepth 2 -name 'SKILL.md' 2>/dev/null | wc -l | tr -d ' ')
hooks_count=$(find "$PAI_ROOT_DIR/hooks" -maxdepth 1 -name '*.hook.ts' 2>/dev/null | wc -l | tr -d ' ')
codex_version=$(codex --version 2>/dev/null | head -1 || echo "unknown")

cat <<BANNER
========================================
Codex_PAI Session Start
Session: $SESSION_ID
Date:    $(now_iso)
Codex:   $codex_version
Skills:  $skills_count
Hooks:   $hooks_count
========================================
BANNER

context_file="$($SCRIPT_DIR/build_context.sh "$STATE_DIR/context-cache-$SESSION_ID.md")"

write_state_json "$STATE_DIR/current-session.json" "{\n  \"session_id\": \"${SESSION_ID}\",\n  \"workspace\": \"${WORKSPACE_DIR}\",\n  \"started_at\": \"$(now_iso)\",\n  \"context_file\": \"${context_file}\"\n}"

if [[ "$(json_get '.features.voice_notifications')" == "true" ]]; then
  curl -s -X POST http://localhost:8888/notify \
    -H "Content-Type: application/json" \
    -d '{"message":"Codex PAI session started"}' >/dev/null 2>&1 || true
fi
