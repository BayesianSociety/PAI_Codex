#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

PROMPT="${1:-}"
MODE="${2:-interactive}" # interactive|strict

if [[ "$(json_get '.features.security_guard')" != "true" ]]; then
  exit 0
fi

mapfile -t patterns < <(json_array_lines '.security.block_patterns')
for pat in "${patterns[@]}"; do
  if [[ "$PROMPT" == *"$pat"* ]]; then
    echo "[SecurityGuard] Matched risky pattern: $pat"
    if [[ "$MODE" == "strict" ]]; then
      echo "[SecurityGuard] Blocked in strict mode."
      exit 2
    fi
    read -r -p "Proceed anyway? [y/N] " ans
    if [[ ! "$ans" =~ ^[Yy]$ ]]; then
      echo "[SecurityGuard] Cancelled by user."
      exit 2
    fi
  fi
done

exit 0
