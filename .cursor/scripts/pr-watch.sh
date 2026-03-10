#!/usr/bin/env bash
# pr-watch.sh — TUI wrapper around pr-status scripts.
# Redraws in-place on each poll. Ctrl+C to stop.
#
# Usage:
#   pr-watch.sh --repo edge-react-gui [--owner EdgeApp] [--user Jon-edge]
#   pr-watch.sh                           # All repos, auto interval, GQL backend
#   pr-watch.sh --backend rest             # Force REST backend
#   pr-watch.sh --interval 60              # Override interval (clamped to safe minimum)
#   pr-watch.sh --budget 0.5               # Reserve 50% of rate limit budget
#   pr-watch.sh --once [...]               # Single poll, no clear, no loop. For agent/script use.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARGS=() INTERVAL="" ONCE=false BACKEND="" BUDGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --interval) INTERVAL="$2"; shift 2 ;;
    --once) ONCE=true; shift ;;
    --backend) BACKEND="$2"; shift 2 ;;
    --budget) BUDGET="$2"; shift 2 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

# Inject --owner default if not already in ARGS
if [[ ${#ARGS[@]} -eq 0 ]] || ! printf '%s\n' "${ARGS[@]}" | grep -q -- '--owner'; then
  ARGS+=(--owner EdgeApp)
fi

# Auto-detect backend: prefer gql if gh CLI is available
if [[ -z "$BACKEND" ]]; then
  if command -v gh &>/dev/null && gh auth status &>/dev/null; then
    BACKEND="gql"
  else
    BACKEND="rest"
  fi
fi

# Select the status script
if [[ "$BACKEND" == "gql" ]]; then
  STATUS_SCRIPT="$SCRIPT_DIR/pr-status-gql.sh"
else
  STATUS_SCRIPT="$SCRIPT_DIR/pr-status.sh"
fi

# Pass budget through if specified
if [[ -n "$BUDGET" ]]; then
  ARGS+=(--budget "$BUDGET")
fi

if $ONCE; then
  NOW=$(date '+%H:%M:%S')
  printf '%s\n' "PR Watch — ${NOW} (${BACKEND})"
  "$STATUS_SCRIPT" "${ARGS[@]}" --format text
  exit $?
fi

# TUI loop
CURRENT_INTERVAL="${INTERVAL:-60}"

while true; do
  OUTPUT=$(FORCE_COLOR=1 "$STATUS_SCRIPT" "${ARGS[@]}" --format text 2>&1) || true
  NOW=$(date '+%H:%M:%S')

  # Parse recommended interval from script output
  RECOMMENDED=$(echo "$OUTPUT" | grep -oP '(?<=^# interval:)\d+' || echo "")

  # Determine actual sleep interval
  if [[ -n "$INTERVAL" ]]; then
    # User-specified interval: clamp to at least the recommended minimum
    if [[ -n "$RECOMMENDED" ]] && [[ "$INTERVAL" -lt "$RECOMMENDED" ]]; then
      CURRENT_INTERVAL="$RECOMMENDED"
    else
      CURRENT_INTERVAL="$INTERVAL"
    fi
  elif [[ -n "$RECOMMENDED" ]]; then
    CURRENT_INTERVAL="$RECOMMENDED"
  fi

  # Strip the machine-readable line from display output
  DISPLAY_OUTPUT=$(echo "$OUTPUT" | grep -v '^# interval:')

  printf '\033[H\033[2J'
  printf '%s\n' "PR Watch — ${NOW}  (${BACKEND}, next in ${CURRENT_INTERVAL}s, Ctrl+C to stop)"
  printf '%s\n' "$DISPLAY_OUTPUT"
  sleep "$CURRENT_INTERVAL"
done
