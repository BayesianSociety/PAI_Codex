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

  requested_skill="$($SCRIPT_DIR/skill_enforcer.sh detect "$prompt" || true)"
  contract_block=""
  if [[ -n "$requested_skill" ]]; then
    contract_block="$($SCRIPT_DIR/skill_enforcer.sh contract "$requested_skill")"
  fi

  last_msg_file="$SESSION_DIR/last-message-$(date +%s).txt"
  context_file="$STATE_DIR/context-cache-$SESSION_ID.md"
  wrapped_prompt="[Codex_PAI Session: $SESSION_ID]\nUse context from: $context_file\n\nUser request:\n$prompt"
  if [[ -n "$contract_block" ]]; then
    wrapped_prompt+="\n\n$contract_block"
  fi

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

  if [[ -n "$requested_skill" ]]; then
    if "$SCRIPT_DIR/skill_enforcer.sh" validate "$requested_skill" "$assistant_msg"; then
      "$SCRIPT_DIR/skill_enforcer.sh" log "$SESSION_ID" "$requested_skill" "true" "$assistant_msg"
    else
      append_jsonl "$TRANSCRIPT_PATH" "system" "skill contract missing marker on first pass; retrying"
      retry_prompt="$wrapped_prompt\n\nCRITICAL RETRY: Previous response invalid because required skill marker was missing.\nYou MUST restart and include exact first line:\nRunning the **${requested_skill}** workflow in the **${requested_skill}** skill."
      if ! "${cmd[@]}" "$retry_prompt"; then
        echo "[Codex_PAI] codex exec failed on skill-contract retry"
        append_jsonl "$TRANSCRIPT_PATH" "system" "codex exec failed on skill-contract retry"
        continue
      fi
      [[ -f "$last_msg_file" ]] && assistant_msg="$(cat "$last_msg_file")"

      if "$SCRIPT_DIR/skill_enforcer.sh" validate "$requested_skill" "$assistant_msg"; then
        "$SCRIPT_DIR/skill_enforcer.sh" log "$SESSION_ID" "$requested_skill" "true" "$assistant_msg"
      else
        "$SCRIPT_DIR/skill_enforcer.sh" log "$SESSION_ID" "$requested_skill" "false" "$assistant_msg"
        append_jsonl "$TRANSCRIPT_PATH" "system" "skill contract failed after retry"
        echo "[Codex_PAI] Skill contract failed for ${requested_skill}. Response rejected."
        continue
      fi
    fi
  fi

  "$SCRIPT_DIR/hooks_stop.sh" "$SESSION_ID" "$assistant_msg" "$TRANSCRIPT_PATH"
done

"$SCRIPT_DIR/hooks_session_end.sh" "$SESSION_ID" "$TRANSCRIPT_PATH"
echo "Session ended: $SESSION_ID"
