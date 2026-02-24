#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

SESSION_ID="$1"
PROMPT="$2"
TRANSCRIPT_PATH="$3"

# Algorithm reminder equivalent
if [[ "$(json_get '.features.user_prompt_submit')" == "true" ]]; then
  echo "[PAI] Algorithm format reminder active for session $SESSION_ID"
fi

# Rating capture
if [[ "$(json_get '.features.rating_capture')" == "true" ]]; then
  if rating_data=$(extract_explicit_rating "$PROMPT"); then
    rating="${rating_data%%|*}"
    comment="${rating_data#*|}"
    bun -e '
const fs = require("fs");
const file = process.argv[1];
const row = {
  timestamp: process.argv[2],
  session_id: process.argv[3],
  rating: Number(process.argv[4]),
  comment: process.argv[5],
  source: "explicit"
};
fs.appendFileSync(file, JSON.stringify(row) + "\n");
' "$SIGNALS_DIR/ratings.jsonl" "$(now_iso)" "$SESSION_ID" "$rating" "$comment"
    echo "[PAI] Captured explicit rating: $rating"
  fi
fi

# Auto work creation
if [[ "$(json_get '.features.auto_work_creation')" == "true" ]] && is_substantive_prompt "$PROMPT"; then
  work_day_dir="$WORK_DIR/$(today)"
  mkdir -p "$work_day_dir"

  safe_task="$(slugify "$PROMPT")"
  [[ -z "$safe_task" ]] && safe_task="task"
  task_dir="$work_day_dir/${SESSION_ID}-${safe_task}"

  if [[ ! -d "$task_dir" ]]; then
    mkdir -p "$task_dir"
    cat > "$task_dir/META.yaml" <<META
session_id: "$SESSION_ID"
created_at: "$(now_iso)"
status: "ACTIVE"
title: "${PROMPT:0:120}"
META
  fi

  bun -e '
const fs = require("fs");
const file = process.argv[1];
const row = {
  session_id: process.argv[2],
  task_dir: process.argv[3],
  title: process.argv[4],
  last_update: process.argv[5],
};
fs.writeFileSync(file, JSON.stringify(row, null, 2));
' "$STATE_DIR/current-work.json" "$SESSION_ID" "$task_dir" "${PROMPT:0:120}" "$(now_iso)"
fi

# Session auto name
if [[ "$(json_get '.features.session_auto_name')" == "true" ]]; then
  names_file="$STATE_DIR/session-names.json"
  [[ -f "$names_file" ]] || echo "{}" > "$names_file"
  if [[ -z "$(json_read_field "$names_file" "$SESSION_ID")" ]]; then
    label="$(echo "$PROMPT" | tr '\n' ' ' | awk '{for(i=1;i<=8 && i<=NF;i++) printf $i (i<8 && i<NF?" ":"")}')"
    [[ -z "$label" ]] && label="Session $SESSION_ID"
    bun -e '
const fs = require("fs");
const file = process.argv[1];
const sid = process.argv[2];
const label = process.argv[3];
const data = JSON.parse(fs.readFileSync(file, "utf8"));
data[sid] = label;
fs.writeFileSync(file, JSON.stringify(data, null, 2));
' "$names_file" "$SESSION_ID" "$label"
  fi
fi

# Tab state emulation
write_state_json "$STATE_DIR/tab-state.json" "{\n  \"session_id\": \"${SESSION_ID}\",\n  \"state\": \"working\",\n  \"updated_at\": \"$(now_iso)\"\n}"

append_jsonl "$TRANSCRIPT_PATH" "user" "$PROMPT"
