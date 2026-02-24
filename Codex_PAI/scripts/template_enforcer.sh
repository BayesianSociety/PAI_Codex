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

const rootDir = process.argv[1];
const paiRoot = process.argv[2];
const prompt = process.argv[3] || "";

function cleanSpec(raw) {
  let s = (raw || "").trim();
  s = s.replace(/^["`]+/, "").replace(/["`]+$/, "");
  return s;
}

function resolveTemplate(spec) {
  if (!spec) return "";
  const candidates = [];
  if (path.isAbsolute(spec)) {
    candidates.push(spec);
  } else {
    candidates.push(path.join(rootDir, spec));
    candidates.push(path.join(paiRoot, spec));
    candidates.push(path.join(paiRoot, "skills", spec));
  }
  if (!path.extname(spec)) {
    const more = [];
    for (const c of candidates) more.push(c + ".md");
    candidates.push(...more);
  }
  for (const c of candidates) {
    if (fs.existsSync(c) && fs.statSync(c).isFile()) return c;
  }
  return "";
}

const patterns = [
  /^\s*template\s*:\s*(.+)\s*$/im,
  /^\s*use\s+template\s*:\s*(.+)\s*$/im,
  /\buse\s+the\s+template\s+at\s+([^\s]+)/i,
];

let spec = "";
for (const re of patterns) {
  const m = prompt.match(re);
  if (m && m[1]) {
    spec = cleanSpec(m[1]);
    break;
  }
}

const resolved = resolveTemplate(spec);
if (resolved) process.stdout.write(resolved);
' "$ROOT_DIR" "$PAI_ROOT_DIR" "$prompt"
    ;;

  contract)
    template_path="${1:-}"
    [[ -f "$template_path" ]] || exit 0
    bun -e '
const fs = require("fs");
const file = process.argv[1];
const text = fs.readFileSync(file, "utf8");
const lines = text.split(/\r?\n/);
const headings = [];
for (const l of lines) {
  const m = l.match(/^\s{0,3}#{1,6}\s+(.+?)\s*$/);
  if (m) headings.push(m[1].trim());
}
const unique = [...new Set(headings)].slice(0, 24);
const preview = lines.slice(0, 180).join("\n");

let out = "TEMPLATE CONTRACT (MANDATORY):\n";
out += `- You MUST follow template file: ${file}\n`;
if (unique.length > 0) {
  out += "- Required section headings (exact text):\n";
  for (const h of unique) out += `  - ${h}\n`;
  out += "- Keep those headings in your final response.\n";
} else {
  out += "- Reproduce the template structure faithfully in your final response.\n";
}
out += "- If template structure is missing, the response is invalid and must be regenerated.\n";
out += "\nTemplate preview:\n```md\n" + preview + "\n```";
process.stdout.write(out);
' "$template_path"
    ;;

  validate)
    template_path="${1:-}"
    msg="${2:-}"
    [[ -f "$template_path" ]] || exit 1
    bun -e '
const fs = require("fs");

const file = process.argv[1];
const msg = process.argv[2] || "";

const tpl = fs.readFileSync(file, "utf8").split(/\r?\n/);
const headings = [];
for (const l of tpl) {
  const m = l.match(/^\s{0,3}#{1,6}\s+(.+?)\s*$/);
  if (m) headings.push(m[1].trim());
}
const required = [...new Set(headings)].slice(0, 24);
if (required.length === 0) process.exit(0);

const outLines = msg.split(/\r?\n/).map(s => s.trim());
for (const h of required) {
  const ok = outLines.some(l => {
    const m = l.match(/^#{1,6}\s+(.+?)\s*$/);
    return m && m[1].trim().toLowerCase() === h.toLowerCase();
  });
  if (!ok) process.exit(1);
}
process.exit(0);
' "$template_path" "$msg"
    ;;

  log)
    session_id="${1:-}"
    template_path="${2:-}"
    confirmed="${3:-false}"
    assistant_msg="${4:-}"
    [[ -n "$session_id" ]] || exit 0
    [[ -n "$template_path" ]] || exit 0

    bun -e '
const fs = require("fs");
const path = require("path");
const file = process.argv[1];
const row = {
  timestamp: new Date().toISOString(),
  session_id: process.argv[2],
  template: process.argv[3],
  template_name: path.basename(process.argv[3]),
  confirmed: process.argv[4] === "true",
  reason: process.argv[4] === "true" ? "template_validated" : "template_missing_after_retry",
  first_line: ((process.argv[5] || "").split(/\r?\n/).find(l => l.trim().length > 0) || "").trim(),
};
fs.appendFileSync(file, JSON.stringify(row) + "\n");
' "$STATE_DIR/template-contracts.jsonl" "$session_id" "$template_path" "$confirmed" "$assistant_msg"
    ;;

  *)
    echo "Usage: template_enforcer.sh {detect|contract|validate|log} ..."
    exit 2
    ;;
esac
