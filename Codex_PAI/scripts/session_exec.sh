#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

if [[ $# -lt 1 ]]; then
  echo "Usage: session_exec.sh \"prompt\" [--model MODEL] [--search] [--cd DIR]"
  exit 1
fi

PROMPT="$1"
shift || true

MODEL=""
SEARCH="false"
WORKSPACE_DIR="$(pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)
      MODEL="$2"
      shift 2
      ;;
    --search)
      SEARCH="true"
      shift
      ;;
    --cd)
      WORKSPACE_DIR="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

"$SCRIPT_DIR/preflight.sh"

SESSION_ID="$(new_session_id)"
SESSION_DIR="$SESSIONS_DIR/$SESSION_ID"
TRANSCRIPT_PATH="$SESSION_DIR/transcript.jsonl"
LAST_MSG_PATH="$SESSION_DIR/last-message.txt"
mkdir -p "$SESSION_DIR"

"$SCRIPT_DIR/hooks_session_start.sh" "$SESSION_ID" "$WORKSPACE_DIR"
"$SCRIPT_DIR/security_guard.sh" "$PROMPT" strict
"$SCRIPT_DIR/hooks_user_prompt_submit.sh" "$SESSION_ID" "$PROMPT" "$TRANSCRIPT_PATH"

context_file="$STATE_DIR/context-cache-$SESSION_ID.md"
wrapped_prompt="[Codex_PAI Session: $SESSION_ID]\nUse context from: $context_file\n\nUser request:\n$PROMPT"

cmd=(codex)
if [[ "$SEARCH" == "true" ]]; then
  cmd+=(--search)
fi
cmd+=(exec --skip-git-repo-check -C "$WORKSPACE_DIR" -s "$(json_get '.codex.sandbox')" -o "$LAST_MSG_PATH")
if [[ -n "$MODEL" ]]; then
  cmd+=(--model "$MODEL")
elif [[ -n "$(json_get '.codex.model')" ]]; then
  default_model="$(json_get '.codex.model')"
  [[ -n "$default_model" ]] && cmd+=(--model "$default_model")
fi
if ! "${cmd[@]}" "$wrapped_prompt"; then
  append_jsonl "$TRANSCRIPT_PATH" "system" "codex exec failed"
fi

assistant_msg=""
if [[ -f "$LAST_MSG_PATH" ]]; then
  assistant_msg="$(cat "$LAST_MSG_PATH")"
fi

"$SCRIPT_DIR/hooks_stop.sh" "$SESSION_ID" "$assistant_msg" "$TRANSCRIPT_PATH"
"$SCRIPT_DIR/hooks_session_end.sh" "$SESSION_ID" "$TRANSCRIPT_PATH"

echo "Session completed: $SESSION_ID"
