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

  requested_agent="$($SCRIPT_DIR/agent_logger.sh detect "$prompt" || true)"
  if [[ -n "$requested_agent" ]]; then
    "$SCRIPT_DIR/agent_logger.sh" log "$SESSION_ID" "$requested_agent" "agent_profile_prompt" "Use this agent profile as authoritative behavior"
  fi

  requested_skill="$($SCRIPT_DIR/skill_enforcer.sh detect "$prompt" || true)"
  skill_contract_block=""
  if [[ -n "$requested_skill" ]]; then
    skill_contract_block="$($SCRIPT_DIR/skill_enforcer.sh contract "$requested_skill")"
  fi

  requested_template="$($SCRIPT_DIR/template_enforcer.sh detect "$prompt" || true)"
  template_contract_block=""
  if [[ -n "$requested_template" ]]; then
    template_contract_block="$($SCRIPT_DIR/template_enforcer.sh contract "$requested_template")"
  fi

  last_msg_file="$SESSION_DIR/last-message-$(date +%s).txt"
  context_file="$STATE_DIR/context-cache-$SESSION_ID.md"
  wrapped_prompt="[Codex_PAI Session: $SESSION_ID]\nUse context from: $context_file\n\nUser request:\n$prompt"
  if [[ -n "$skill_contract_block" ]]; then
    wrapped_prompt+="\n\n$skill_contract_block"
  fi
  if [[ -n "$template_contract_block" ]]; then
    wrapped_prompt+="\n\n$template_contract_block"
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

  skill_ok="true"
  template_ok="true"
  skill_retry_note=""
  template_retry_note=""

  if [[ -n "$requested_skill" ]]; then
    if ! "$SCRIPT_DIR/skill_enforcer.sh" validate "$requested_skill" "$assistant_msg"; then
      skill_ok="false"
      skill_retry_note="Skill marker missing. Required first line: Running the **${requested_skill}** workflow in the **${requested_skill}** skill."
    fi
  fi

  if [[ -n "$requested_template" ]]; then
    if ! "$SCRIPT_DIR/template_enforcer.sh" validate "$requested_template" "$assistant_msg"; then
      template_ok="false"
      template_retry_note="Template structure missing for ${requested_template}."
    fi
  fi

  if [[ "$skill_ok" == "false" || "$template_ok" == "false" ]]; then
    append_jsonl "$TRANSCRIPT_PATH" "system" "contract validation failed on first pass; retrying"
    retry_prompt="$wrapped_prompt\n\nCRITICAL RETRY: Previous response invalid."
    [[ -n "$skill_retry_note" ]] && retry_prompt+="\n- ${skill_retry_note}"
    [[ -n "$template_retry_note" ]] && retry_prompt+="\n- ${template_retry_note}"
    retry_prompt+="\nRegenerate the full response and satisfy all contracts exactly."

    if ! "${cmd[@]}" "$retry_prompt"; then
      echo "[Codex_PAI] codex exec failed on contract retry"
      append_jsonl "$TRANSCRIPT_PATH" "system" "codex exec failed on contract retry"
      continue
    fi
    [[ -f "$last_msg_file" ]] && assistant_msg="$(cat "$last_msg_file")"

    if [[ -n "$requested_skill" ]]; then
      "$SCRIPT_DIR/skill_enforcer.sh" validate "$requested_skill" "$assistant_msg" && skill_ok="true" || skill_ok="false"
    fi
    if [[ -n "$requested_template" ]]; then
      "$SCRIPT_DIR/template_enforcer.sh" validate "$requested_template" "$assistant_msg" && template_ok="true" || template_ok="false"
    fi
  fi

  if [[ -n "$requested_skill" ]]; then
    "$SCRIPT_DIR/skill_enforcer.sh" log "$SESSION_ID" "$requested_skill" "$skill_ok" "$assistant_msg"
  fi
  if [[ -n "$requested_template" ]]; then
    "$SCRIPT_DIR/template_enforcer.sh" log "$SESSION_ID" "$requested_template" "$template_ok" "$assistant_msg"
  fi

  if [[ "$skill_ok" == "false" || "$template_ok" == "false" ]]; then
    append_jsonl "$TRANSCRIPT_PATH" "system" "contract failed after retry"
    echo "[Codex_PAI] Contract failed (skill/template). Response rejected."
    continue
  fi

  "$SCRIPT_DIR/hooks_stop.sh" "$SESSION_ID" "$assistant_msg" "$TRANSCRIPT_PATH"
done

"$SCRIPT_DIR/hooks_session_end.sh" "$SESSION_ID" "$TRANSCRIPT_PATH"
echo "Session ended: $SESSION_ID"
