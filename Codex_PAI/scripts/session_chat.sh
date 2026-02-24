#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

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
mkdir -p "$SESSION_DIR"

"$SCRIPT_DIR/hooks_session_start.sh" "$SESSION_ID" "$WORKSPACE_DIR"

echo "Codex_PAI chat session: $SESSION_ID"
echo "Type /exit to end, /status for status."

while true; do
  read -r -p "you> " prompt || break
  if [[ -z "$prompt" ]]; then
    continue
  fi

  case "$prompt" in
    /exit|/quit)
      break
      ;;
    /status)
      echo "session_id: $SESSION_ID"
      echo "transcript: $TRANSCRIPT_PATH"
      continue
      ;;
  esac

  if ! "$SCRIPT_DIR/security_guard.sh" "$prompt" interactive; then
    continue
  fi

  "$SCRIPT_DIR/hooks_user_prompt_submit.sh" "$SESSION_ID" "$prompt" "$TRANSCRIPT_PATH"

  last_msg_file="$SESSION_DIR/last-message-$(date +%s).txt"
  context_file="$STATE_DIR/context-cache-$SESSION_ID.md"
  wrapped_prompt="[Codex_PAI Session: $SESSION_ID]\nUse context from: $context_file\n\nUser request:\n$prompt"

  cmd=(codex)
  if [[ "$SEARCH" == "true" ]]; then
    cmd+=(--search)
  fi
  cmd+=(exec --skip-git-repo-check -C "$WORKSPACE_DIR" -s "$(json_get '.codex.sandbox')" -o "$last_msg_file")
  if [[ -n "$MODEL" ]]; then
    cmd+=(--model "$MODEL")
  elif [[ -n "$(json_get '.codex.model')" ]]; then
    default_model="$(json_get '.codex.model')"
    [[ -n "$default_model" ]] && cmd+=(--model "$default_model")
  fi
  if ! "${cmd[@]}" "$wrapped_prompt"; then
    echo "[Codex_PAI] codex exec failed"
    append_jsonl "$TRANSCRIPT_PATH" "system" "codex exec failed for prompt"
    continue
  fi

  assistant_msg=""
  [[ -f "$last_msg_file" ]] && assistant_msg="$(cat "$last_msg_file")"
  "$SCRIPT_DIR/hooks_stop.sh" "$SESSION_ID" "$assistant_msg" "$TRANSCRIPT_PATH"
done

"$SCRIPT_DIR/hooks_session_end.sh" "$SESSION_ID" "$TRANSCRIPT_PATH"
echo "Session ended: $SESSION_ID"
