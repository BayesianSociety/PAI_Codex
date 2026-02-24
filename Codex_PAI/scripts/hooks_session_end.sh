#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

SESSION_ID="$1"
TRANSCRIPT_PATH="$2"

# Session summary
summary_file="$SESSIONS_DIR/$SESSION_ID/summary.md"
mkdir -p "$(dirname "$summary_file")"

{
  echo "# Session Summary"
  echo
  echo "- Session: $SESSION_ID"
  echo "- Ended: $(now_iso)"
  echo
  echo "## Last Transcript Entries"
  tail -n 8 "$TRANSCRIPT_PATH" 2>/dev/null || true
} > "$summary_file"

# Relationship memory extraction (simple heuristic)
if [[ -f "$TRANSCRIPT_PATH" ]]; then
  rel_file="$REL_DIR/relationship-notes-$(today).md"
  bun -e '
const fs = require("fs");
const file = process.argv[1];
const lines = fs.readFileSync(file, "utf8").split(/\n+/).filter(Boolean);
for (const line of lines) {
  try {
    const row = JSON.parse(line);
    if (row.role === "user" && typeof row.text === "string") process.stdout.write(row.text + "\n");
  } catch {}
}
' "$TRANSCRIPT_PATH" > "$STATE_DIR/user-lines.tmp" || true

  if command -v rg >/dev/null 2>&1; then
    rg -i "\b(i prefer|my preference|i like|i dislike|my goal|my workflow)\b" \
      "$STATE_DIR/user-lines.tmp" > "$STATE_DIR/relationship-candidates.txt" || true
  else
    grep -Ei "(i prefer|my preference|i like|i dislike|my goal|my workflow)" \
      "$STATE_DIR/user-lines.tmp" > "$STATE_DIR/relationship-candidates.txt" || true
  fi
  rm -f "$STATE_DIR/user-lines.tmp"

  if [[ -s "$STATE_DIR/relationship-candidates.txt" ]]; then
    {
      echo "## $(now_iso) | session $SESSION_ID"
      cat "$STATE_DIR/relationship-candidates.txt"
      echo
    } >> "$rel_file"
  fi
fi

# Work completion
if [[ -f "$STATE_DIR/current-work.json" ]]; then
  sid="$(json_read_field "$STATE_DIR/current-work.json" "session_id")"
  if [[ "$sid" == "$SESSION_ID" ]]; then
    task_dir="$(json_read_field "$STATE_DIR/current-work.json" "task_dir")"
    if [[ -n "$task_dir" && -f "$task_dir/META.yaml" ]]; then
      sed -i 's/status: "ACTIVE"/status: "COMPLETED"/g' "$task_dir/META.yaml" || true
    fi
    rm -f "$STATE_DIR/current-work.json"
  fi
fi

# Counts
skills_count=$(find "$PAI_ROOT_DIR/skills" -maxdepth 2 -name 'SKILL.md' 2>/dev/null | wc -l | tr -d ' ')
hooks_count=$(find "$PAI_ROOT_DIR/hooks" -maxdepth 1 -name '*.hook.ts' 2>/dev/null | wc -l | tr -d ' ')
sessions_count=$(find "$SESSIONS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
ratings_count=$(wc -l < "$SIGNALS_DIR/ratings.jsonl" 2>/dev/null || echo 0)

write_state_json "$STATE_DIR/counts.json" "{\n  \"updated_at\": \"$(now_iso)\",\n  \"skills\": ${skills_count},\n  \"hooks\": ${hooks_count},\n  \"sessions\": ${sessions_count},\n  \"ratings\": ${ratings_count}\n}"

# Integrity check hash set
if [[ "$(json_get '.features.integrity_check')" == "true" ]]; then
  hash_file_list "$STATE_DIR/integrity-hashes.txt" \
    "$PAI_ROOT_DIR/settings.json" \
    "$PAI_ROOT_DIR/README.md" \
    "$PAI_ROOT_DIR/skills/PAI/SKILL.md"
fi

rm -f "$STATE_DIR/current-session.json"
