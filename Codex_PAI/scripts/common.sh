#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_ADJACENT_ROOT="$(cd "$ROOT_DIR/.." && pwd)"

detect_pai_root() {
  if [[ -n "${PAI_ROOT:-}" ]]; then
    echo "$PAI_ROOT"
    return 0
  fi
  if [[ -f "$ROOT_DIR/skills/PAI/SKILL.md" ]]; then
    echo "$ROOT_DIR"
    return 0
  fi
  if [[ -f "$DEFAULT_ADJACENT_ROOT/skills/PAI/SKILL.md" ]]; then
    echo "$DEFAULT_ADJACENT_ROOT"
    return 0
  fi
  if [[ -f "$HOME/.claude/skills/PAI/SKILL.md" ]]; then
    echo "$HOME/.claude"
    return 0
  fi
  echo "$DEFAULT_ADJACENT_ROOT"
}

PAI_ROOT_DIR="$(detect_pai_root)"
export PAI_ROOT_DIR
CONFIG_FILE="$ROOT_DIR/config/wrapper.json"
MEMORY_DIR="$ROOT_DIR/MEMORY"
STATE_DIR="$MEMORY_DIR/STATE"
SESSIONS_DIR="$MEMORY_DIR/SESSIONS"
WORK_DIR="$MEMORY_DIR/WORK"
LEARNING_DIR="$MEMORY_DIR/LEARNING"
REL_DIR="$MEMORY_DIR/RELATIONSHIP"
SIGNALS_DIR="$LEARNING_DIR/SIGNALS"

mkdir -p "$STATE_DIR" "$SESSIONS_DIR" "$WORK_DIR" "$LEARNING_DIR" "$REL_DIR" "$SIGNALS_DIR"

now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

today() {
  date +"%Y-%m-%d"
}

slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//' | cut -c1-48
}

new_session_id() {
  printf "%s-%s" "$(date +%Y%m%d-%H%M%S)" "$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')"
}

json_get() {
  local key="$1"
  bun -e '
const fs = require("fs");
const cfg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const key = process.argv[2];
function get(obj, path) {
  return path.split(".").reduce((acc, part) => (acc && part in acc ? acc[part] : undefined), obj);
}
const clean = key.replace(/^\./, "");
const value = get(cfg, clean);
if (value === undefined || value === null) process.stdout.write("");
else if (typeof value === "object") process.stdout.write(JSON.stringify(value));
else process.stdout.write(String(value));
' "$CONFIG_FILE" "$key"
}

append_jsonl() {
  local file="$1"
  local role="$2"
  local text="$3"
  mkdir -p "$(dirname "$file")"
  bun -e '
const fs = require("fs");
const file = process.argv[1];
const role = process.argv[2];
const ts = process.argv[3];
const text = process.argv[4];
const row = JSON.stringify({ timestamp: ts, role, text });
fs.appendFileSync(file, row + "\n");
' "$file" "$role" "$(now_iso)" "$text"
}

write_state_json() {
  local file="$1"
  local json="$2"
  mkdir -p "$(dirname "$file")"
  printf '%b\n' "$json" > "$file"
}

is_substantive_prompt() {
  local p
  p="$(echo "$1" | tr -d '\n' | sed 's/^ *//;s/ *$//')"
  if [[ "${#p}" -lt 12 ]]; then
    return 1
  fi
  if [[ "$p" =~ ^(hi|hello|hey|ok|okay|thanks|thx|yes|no|cool|nice|got\ it|continue|proceed)$ ]]; then
    return 1
  fi
  return 0
}

extract_explicit_rating() {
  local p="$1"
  if [[ "$p" =~ ^[[:space:]]*([1-9]|10)([[:space:]]*[-:][[:space:]]*(.*))?[[:space:]]*$ ]]; then
    echo "${BASH_REMATCH[1]}|${BASH_REMATCH[3]:-}"
    return 0
  fi
  return 1
}

check_codex_login() {
  local status
  if ! status="$(codex login status 2>&1)"; then
    echo "ERROR: Could not query codex login status."
    return 1
  fi
  if [[ "$status" == *"Logged in using ChatGPT"* ]]; then
    return 0
  fi
  echo "ERROR: Codex is not logged in with ChatGPT web auth."
  echo "Run: codex login"
  echo "Do not use --with-api-key for this wrapper."
  return 1
}

hash_file_list() {
  local out="$1"
  shift
  : > "$out"
  for f in "$@"; do
    if [[ -f "$f" ]]; then
      sha256sum "$f" >> "$out"
    fi
  done
}

json_array_lines() {
  local key="$1"
  bun -e '
const fs = require("fs");
const cfg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const key = process.argv[2].replace(/^\./, "");
const value = key.split(".").reduce((acc, part) => (acc && part in acc ? acc[part] : undefined), cfg);
if (Array.isArray(value)) {
  for (const item of value) process.stdout.write(String(item) + "\n");
}
' "$CONFIG_FILE" "$key"
}

json_write_obj_file() {
  local file="$1"
  local json="$2"
  mkdir -p "$(dirname "$file")"
  printf '%s\n' "$json" > "$file"
}

json_read_field() {
  local file="$1"
  local field="$2"
  bun -e '
const fs = require("fs");
const file = process.argv[1];
const field = process.argv[2];
if (!fs.existsSync(file)) process.exit(0);
try {
  const obj = JSON.parse(fs.readFileSync(file, "utf8"));
  const value = field.split(".").reduce((acc, part) => (acc && part in acc ? acc[part] : undefined), obj);
  if (value !== undefined && value !== null) process.stdout.write(String(value));
} catch {}
' "$file" "$field"
}
