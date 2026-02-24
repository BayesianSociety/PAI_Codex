#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

cmd="${1:-}"
shift || true

case "$cmd" in
  detect)
    prompt="${1:-}"
    bun -e '
const fs = require("fs");
const path = require("path");
const paiRoot = process.argv[1];
const prompt = process.argv[2] || "";

const skillsDir = path.join(paiRoot, "skills");
let valid = new Set();
try {
  for (const name of fs.readdirSync(skillsDir)) {
    const skillFile = path.join(skillsDir, name, "SKILL.md");
    if (fs.existsSync(skillFile)) valid.add(name.toLowerCase());
  }
} catch {}

const patterns = [
  /use\s+the\s+([A-Za-z][A-Za-z0-9]+)\s+skill\b/gi,
  /([A-Za-z][A-Za-z0-9]+)\s+skill\s+workflow\b/gi,
  /run\s+the\s+([A-Za-z][A-Za-z0-9]+)\s+skill\b/gi,
];

for (const re of patterns) {
  for (const m of prompt.matchAll(re)) {
    const s = m[1];
    if (!s) continue;
    if (valid.has(s.toLowerCase())) {
      process.stdout.write(s);
      process.exit(0);
    }
  }
}
' "$PAI_ROOT_DIR" "$prompt"
    ;;

  contract)
    skill="${1:-}"
    [[ -n "$skill" ]] || exit 0
    cat <<CONTRACT
SKILL CONTRACT (MANDATORY):
- You MUST use the ${skill} skill workflow.
- Your FIRST non-empty output line MUST be exactly:
Running the **${skill}** workflow in the **${skill}** skill.
- If this exact line is missing, the response is invalid and must be regenerated.
CONTRACT
    ;;

  validate)
    skill="${1:-}"
    msg="${2:-}"
    [[ -n "$skill" ]] || exit 1
    bun -e '
const skill = process.argv[1];
const msg = process.argv[2] || "";
const first = (msg.split(/\r?\n/).find(l => l.trim().length > 0) || "").trim();
const expected = `Running the **${skill}** workflow in the **${skill}** skill.`;
if (first === expected) process.exit(0);
process.exit(1);
' "$skill" "$msg"
    ;;

  log)
    session_id="${1:-}"
    requested_skill="${2:-}"
    confirmed="${3:-false}"
    assistant_msg="${4:-}"
    [[ -n "$session_id" ]] || exit 0
    [[ -n "$requested_skill" ]] || exit 0

    bun -e '
const fs = require("fs");
const file = process.argv[1];
const row = {
  timestamp: new Date().toISOString(),
  session_id: process.argv[2],
  requested_skill: process.argv[3],
  confirmed: process.argv[4] === "true",
  reason: process.argv[4] === "true" ? "marker_present" : "marker_missing_after_retry",
  first_line: ((process.argv[5] || "").split(/\r?\n/).find(l => l.trim().length > 0) || "").trim(),
};
fs.appendFileSync(file, JSON.stringify(row) + "\n");
' "$STATE_DIR/skill-contracts.jsonl" "$session_id" "$requested_skill" "$confirmed" "$assistant_msg"
    ;;

  *)
    echo "Usage: skill_enforcer.sh {detect|contract|validate|log} ..."
    exit 2
    ;;
esac
