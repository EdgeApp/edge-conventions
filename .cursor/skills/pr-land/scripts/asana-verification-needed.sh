#!/usr/bin/env bash
# asana-verification-needed.sh — Pure Asana script (no GitHub dependency).
# Updates task status from "Publish Needed" → "Verification Needed" and unsets assignee.
#
# Input: JSON array of {taskGid, label} on stdin
#   taskGid  — Asana task GID (required)
#   label    — Human-readable label for reporting, e.g. "edge-react-gui#123" (optional)
#
# The caller is responsible for extracting taskGid from PR descriptions before
# invoking this script. See pr-land.md Phase 8 for the extraction pattern.
#
# Requires: ASANA_TOKEN env var, jq
#
# Exit codes:
#   0 = All tasks updated successfully
#   1 = One or more tasks failed (see JSON output for details)
#   2 = Missing env vars or invalid input
set -euo pipefail

if [[ -z "${ASANA_TOKEN:-}" ]]; then
  echo "Error: ASANA_TOKEN not set" >&2; exit 2
fi

INPUT=$(cat)
if [[ -z "$INPUT" ]]; then
  echo "Error: No input. Pipe JSON array of {taskGid, label} on stdin." >&2
  exit 2
fi

# Airbitz.co workspace field GIDs
STATUS_FIELD="1190660107346181"
PUBLISH_NEEDED="1191304757575656"
VERIFICATION_NEEDED="1190660107348340"
ASANA_API="https://app.asana.com/api/1.0"

UPDATED='[]'
ERRORS='[]'

COUNT=$(echo "$INPUT" | jq 'length')
for ((i = 0; i < COUNT; i++)); do
  TASK_GID=$(echo "$INPUT" | jq -r ".[$i].taskGid")
  LABEL=$(echo "$INPUT" | jq -r ".[$i].label // .[$i].taskGid")

  if [[ -z "$TASK_GID" || "$TASK_GID" == "null" ]]; then
    ERRORS=$(echo "$ERRORS" | jq --arg l "$LABEL" \
      '. + [{label: $l, error: "Missing taskGid"}]')
    continue
  fi

  # Fetch task and validate status
  TASK=$(curl -sf "$ASANA_API/tasks/$TASK_GID?opt_fields=name,assignee.name,custom_fields.gid,custom_fields.enum_value.gid,custom_fields.enum_value.name" \
    -H "Authorization: Bearer $ASANA_TOKEN" 2>&1) || {
    ERRORS=$(echo "$ERRORS" | jq --arg l "$LABEL" --arg e "Failed to fetch task $TASK_GID" \
      '. + [{label: $l, error: $e}]')
    continue
  }

  CURRENT_STATUS=$(echo "$TASK" | jq -r \
    ".data.custom_fields[] | select(.gid == \"$STATUS_FIELD\") | .enum_value.gid // empty")
  CURRENT_STATUS_NAME=$(echo "$TASK" | jq -r \
    ".data.custom_fields[] | select(.gid == \"$STATUS_FIELD\") | .enum_value.name // empty")
  TASK_NAME=$(echo "$TASK" | jq -r '.data.name')
  ASSIGNEE_NAME=$(echo "$TASK" | jq -r '.data.assignee.name // empty')

  if [[ "$CURRENT_STATUS" != "$PUBLISH_NEEDED" ]]; then
    ERRORS=$(echo "$ERRORS" | jq \
      --arg l "$LABEL" --arg gid "$TASK_GID" --arg name "$TASK_NAME" \
      --arg s "Status is '${CURRENT_STATUS_NAME:-(not set)}', expected 'Publish Needed'" \
      '. + [{label: $l, taskGid: $gid, taskName: $name, error: $s}]')
    continue
  fi

  # Update: unset assignee + set Verification Needed
  UPDATE_BODY=$(jq -n \
    --arg sf "$STATUS_FIELD" --arg vn "$VERIFICATION_NEEDED" \
    '{data: {assignee: null, custom_fields: {($sf): $vn}}}')

  curl -sf -X PUT "$ASANA_API/tasks/$TASK_GID" \
    -H "Authorization: Bearer $ASANA_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$UPDATE_BODY" >/dev/null 2>&1 || {
    ERRORS=$(echo "$ERRORS" | jq --arg l "$LABEL" --arg e "Failed to update task $TASK_GID" \
      '. + [{label: $l, error: $e}]')
    continue
  }

  UPDATED=$(echo "$UPDATED" | jq \
    --arg l "$LABEL" --arg gid "$TASK_GID" --arg name "$TASK_NAME" --arg prev "$ASSIGNEE_NAME" \
    '. + [{label: $l, taskGid: $gid, taskName: $name, previousAssignee: $prev, statusChange: "Publish Needed → Verification Needed"}]')
done

jq -n --argjson u "$UPDATED" --argjson e "$ERRORS" '{updated: $u, errors: $e}'

ERROR_COUNT=$(echo "$ERRORS" | jq 'length')
[[ "$ERROR_COUNT" -gt 0 ]] && exit 1
exit 0
