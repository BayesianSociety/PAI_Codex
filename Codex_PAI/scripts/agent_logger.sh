#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

cmd="${1:-}"
shift || true

case "$cmd" in
  detect)
    prompt="${1:-}"
    bun -e '
const text = process.argv[1] || "";

function firstMatch(re) {
  const m = text.match(re);
  return m && m[1] ? m[1].trim() : "";
}

// Preferred signal: agent wrapper prompt preamble + YAML name field.
if (/Use this agent profile as authoritative behavior:/i.test(text)) {
  const name = firstMatch(/(?:^|\n)\s*name:\s*([A-Za-z][A-Za-z0-9_-]*)\s*(?:\n|$)/i);
  if (name) {
    process.stdout.write(name);
    process.exit(0);
  }
}

// Fallback: explicit instruction mentioning "<Name> agent".
const alt = firstMatch(/\boperate as a\s+([A-Za-z][A-Za-z0-9_-]*)\s+agent\b/i);
if (alt) process.stdout.write(alt);
' "$prompt"
    ;;

  log)
    session_id="${1:-}"
    agent_name="${2:-}"
    signal="${3:-agent_profile_prompt}"
    evidence="${4:-}"
    [[ -n "$session_id" ]] || exit 0
    [[ -n "$agent_name" ]] || exit 0

    bun -e '
const fs = require("fs");
const file = process.argv[1];
const row = {
  timestamp: new Date().toISOString(),
  session_id: process.argv[2],
  agent: process.argv[3],
  signal: process.argv[4],
  evidence: process.argv[5] || "",
  strict_confirmed: true
};
fs.appendFileSync(file, JSON.stringify(row) + "\n");
' "$STATE_DIR/agents-used.jsonl" "$session_id" "$agent_name" "$signal" "$evidence"
    ;;

  *)
    echo "Usage: agent_logger.sh {detect|log} ..."
    exit 2
    ;;
esac
