#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

SESSION_ID="$1"
ASSISTANT_MSG="$2"
TRANSCRIPT_PATH="$3"

append_jsonl "$TRANSCRIPT_PATH" "assistant" "$ASSISTANT_MSG"

summary="$(echo "$ASSISTANT_MSG" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-180)"

write_state_json "$STATE_DIR/tab-state.json" "{\n  \"session_id\": \"${SESSION_ID}\",\n  \"state\": \"idle\",\n  \"updated_at\": \"$(now_iso)\"\n}"

bun -e '
const fs = require("fs");
const file = process.argv[1];
const row = { timestamp: process.argv[2], session_id: process.argv[3], summary: process.argv[4] };
fs.appendFileSync(file, JSON.stringify(row) + "\n");
' "$STATE_DIR/stop-events.jsonl" "$(now_iso)" "$SESSION_ID" "$summary"

# Strict skill-use confirmation logger (deterministic signals only)
"$SCRIPT_DIR/skill_logger.sh" "$SESSION_ID" "$ASSISTANT_MSG"

if [[ "$(json_get '.features.voice_notifications')" == "true" ]] && [[ -n "$summary" ]]; then
  payload="{\"message\":\"${summary//\"/\\\"}\"}"
  curl -s -X POST http://localhost:8888/notify \
    -H "Content-Type: application/json" \
    -d "$payload" >/dev/null 2>&1 || true
fi
