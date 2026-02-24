#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

if ! command -v codex >/dev/null 2>&1; then
  echo "ERROR: codex CLI not found in PATH."
  exit 1
fi

if ! command -v bun >/dev/null 2>&1; then
  echo "ERROR: bun runtime not found in PATH."
  echo "Install bun: https://bun.sh"
  exit 1
fi

check_codex_login

if [[ "$(json_get '.require_web_login')" == "true" ]]; then
  status="$(codex login status 2>&1 || true)"
  if [[ "$status" == *"API key"* ]]; then
    echo "ERROR: Wrapper requires ChatGPT web login, not API key auth."
    echo "Run: codex logout && codex login"
    exit 1
  fi
fi

if [[ ! -f "$PAI_ROOT_DIR/skills/PAI/SKILL.md" ]]; then
  echo "ERROR: Could not locate PAI root (missing skills/PAI/SKILL.md)."
  echo "Set PAI_ROOT to your PAI release root, for example:"
  echo "  export PAI_ROOT=/path/to/.claude"
  exit 1
fi

exit 0
