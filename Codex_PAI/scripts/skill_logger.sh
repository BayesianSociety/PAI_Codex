#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

SESSION_ID="${1:-}"
ASSISTANT_MSG="${2:-}"

[[ -n "$SESSION_ID" ]] || exit 0
[[ -n "$ASSISTANT_MSG" ]] || exit 0

LOG_FILE="$STATE_DIR/skills-used.jsonl"

# Strict confirmation signals only:
# 1) "... in the **<Skill>** skill"
# 2) explicit path mention: skills/<Skill>/...
# Only logs if <PAI_ROOT>/skills/<Skill>/SKILL.md exists.
bun -e '
const fs = require("fs");
const path = require("path");

const logFile = process.argv[1];
const paiRoot = process.argv[2];
const sessionId = process.argv[3];
const text = process.argv[4] || "";
const timestamp = new Date().toISOString();

const found = new Map();

const explicitRe = new RegExp("in\\s+the\\s+\\*\\*([A-Za-z][A-Za-z0-9]+)\\*\\*\\s+skill", "gi");
for (const m of text.matchAll(explicitRe)) {
  const skill = m[1];
  found.set(skill, {
    signal: "explicit_skill_phrase",
    evidence: m[0],
  });
}

const pathRe = new RegExp("skills/([A-Za-z][A-Za-z0-9]+)/", "g");
for (const m of text.matchAll(pathRe)) {
  const skill = m[1];
  if (!found.has(skill)) {
    found.set(skill, {
      signal: "skills_path_reference",
      evidence: m[0],
    });
  }
}

for (const [skill, meta] of found.entries()) {
  const skillFile = path.join(paiRoot, "skills", skill, "SKILL.md");
  if (!fs.existsSync(skillFile)) continue;

  const row = {
    timestamp,
    session_id: sessionId,
    skill,
    signal: meta.signal,
    evidence: meta.evidence,
    strict_confirmed: true,
  };
  fs.appendFileSync(logFile, JSON.stringify(row) + "\n");
}
' "$LOG_FILE" "$PAI_ROOT_DIR" "$SESSION_ID" "$ASSISTANT_MSG"
