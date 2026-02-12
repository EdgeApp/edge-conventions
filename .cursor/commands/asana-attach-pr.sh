#!/usr/bin/env bash
# asana-attach-pr.sh
# Attach a GitHub PR to an Asana task. Optionally assign to reviewer and set status.
#
# Usage:
#   asana-attach-pr.sh --task <task_gid> --pr-url <pr_url> --pr-title <title> --pr-number <number> \
#     [--assign] [--reviewer <user_gid>] [--implementor <user_gid>]
#
# Requires env vars: ASANA_TOKEN, ASANA_GITHUB_SECRET
#
# Without --assign: only attaches the PR to the task (no assignment or status change).
# With --assign: also assigns to reviewer, sets status to "Review Needed", and
#   auto-populates Est. Review Hrs if empty.
#
# If --assign is used and --reviewer or --implementor are provided, they override
# what's on the task. If the task's Reviewer field is empty and no override is
# given, the script outputs PROMPT_REVIEWER so the calling agent can ask the user
# and re-run with the override. If the Implementor field is empty and no override
# is given, it auto-resolves to the current user via asana-whoami.sh.
#
# Output: One-line summary per action (success/failure/prompt)
set -euo pipefail

TASK_GID=""
PR_URL=""
PR_TITLE=""
PR_NUMBER=""
REVIEWER_OVERRIDE=""
IMPLEMENTOR_OVERRIDE=""
DO_ASSIGN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task) TASK_GID="$2"; shift 2 ;;
    --pr-url) PR_URL="$2"; shift 2 ;;
    --pr-title) PR_TITLE="$2"; shift 2 ;;
    --pr-number) PR_NUMBER="$2"; shift 2 ;;
    --assign) DO_ASSIGN=true; shift ;;
    --reviewer) REVIEWER_OVERRIDE="$2"; shift 2 ;;
    --implementor) IMPLEMENTOR_OVERRIDE="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$TASK_GID" || -z "$PR_URL" || -z "$PR_TITLE" || -z "$PR_NUMBER" ]]; then
  echo "Error: --task, --pr-url, --pr-title, and --pr-number are all required" >&2
  exit 1
fi
if [[ -z "${ASANA_TOKEN:-}" ]]; then
  echo "Error: ASANA_TOKEN not set" >&2; exit 1
fi
if [[ -z "${ASANA_GITHUB_SECRET:-}" ]]; then
  echo "Error: ASANA_GITHUB_SECRET not set" >&2; exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Known field GIDs (airbitz.co workspace)
STATUS_FIELD="1190660107346181"
REVIEW_NEEDED_OPTION="1190660107348334"
REVIEWER_FIELD="1203334388004673"
IMPLEMENTOR_FIELD="1203334386796983"
SPENT_DEV_HRS_FIELD="1202996660964169"
EST_REVIEW_HRS_FIELD="1203002792997295"

# --- Step 1: Attach PR via GitHub integration ---
ATTACH_RESULT=$(curl -s -X POST "https://github.integrations.asana.plus/custom/v1/actions/widget" \
  -H "Authorization: Bearer $ASANA_GITHUB_SECRET" \
  -H "Content-Type: application/json" \
  -d "{
    \"allowedProjects\": [],
    \"blockedProjects\": [],
    \"pullRequestDescription\": \"https://app.asana.com/0/0/$TASK_GID\",
    \"pullRequestName\": $(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$PR_TITLE"),
    \"pullRequestNumber\": $PR_NUMBER,
    \"pullRequestURL\": \"$PR_URL\"
  }" 2>&1)

ATTACH_STATUS=$(echo "$ATTACH_RESULT" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r[0].get('result','unknown'))" 2>/dev/null || echo "error: $ATTACH_RESULT")
echo ">> PR attach: $ATTACH_STATUS"

# Without --assign, stop after attaching
if ! $DO_ASSIGN; then
  exit 0
fi

# --- Step 2: Read task fields (Reviewer + Implementor) ---
TASK_FIELDS=$(curl -s "https://app.asana.com/api/1.0/tasks/$TASK_GID?opt_fields=custom_fields.gid,custom_fields.people_value,custom_fields.number_value" \
  -H "Authorization: Bearer $ASANA_TOKEN")

read_people_field() {
  local field_gid="$1"
  echo "$TASK_FIELDS" | python3 -c "
import sys, json
data = json.load(sys.stdin)['data']
for f in data['custom_fields']:
    if f['gid'] == '$field_gid':
        pv = f.get('people_value', [])
        print(pv[0]['gid'] if pv else '')
        break
" 2>/dev/null || echo ""
}

REVIEWER_GID="${REVIEWER_OVERRIDE:-$(read_people_field "$REVIEWER_FIELD")}"
IMPLEMENTOR_GID="${IMPLEMENTOR_OVERRIDE:-$(read_people_field "$IMPLEMENTOR_FIELD")}"

# Auto-resolve implementor to current user if empty
if [[ -z "$IMPLEMENTOR_GID" ]]; then
  IMPLEMENTOR_GID=$("$SCRIPT_DIR/asana-whoami.sh" 2>/dev/null || true)
  if [[ -n "$IMPLEMENTOR_GID" ]]; then
    IMPLEMENTOR_OVERRIDE="$IMPLEMENTOR_GID"
    echo ">> Implementor: auto-resolved to current user ($IMPLEMENTOR_GID)"
  fi
fi

if [[ -z "$REVIEWER_GID" ]]; then
  echo ">> PROMPT_REVIEWER"
  exit 2
fi

if [[ -z "$IMPLEMENTOR_GID" ]]; then
  echo ">> PROMPT_IMPLEMENTOR"
  exit 2
fi

# --- Step 3: Set Implementor if override was provided ---
if [[ -n "$IMPLEMENTOR_OVERRIDE" ]]; then
  curl -s -X PUT "https://app.asana.com/api/1.0/tasks/$TASK_GID" \
    -H "Authorization: Bearer $ASANA_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"data\":{\"custom_fields\":{\"$IMPLEMENTOR_FIELD\":{\"people_value\":[\"$IMPLEMENTOR_OVERRIDE\"]}}}}" > /dev/null 2>&1 || true
  echo ">> Implementor: set"
fi

# --- Step 4: Assign to reviewer and set status to Review Needed ---
UPDATE_RESULT=$(curl -s -X PUT "https://app.asana.com/api/1.0/tasks/$TASK_GID" \
  -H "Authorization: Bearer $ASANA_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"data\": {
      \"assignee\": \"$REVIEWER_GID\",
      \"custom_fields\": {
        \"$STATUS_FIELD\": \"$REVIEW_NEEDED_OPTION\"
      }
    }
  }" 2>&1)

ASSIGNEE_NAME=$(echo "$UPDATE_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['assignee']['name'])" 2>/dev/null || echo "unknown")
echo ">> Assigned to: $ASSIGNEE_NAME"
echo ">> Status: Review Needed"

# --- Step 5: Auto-populate Est. Review Hrs if empty (non-blocking) ---
python3 -c "
import sys, json
data = json.loads('''$TASK_FIELDS''')['data']
spent_dev = None
est_review = None
for f in data['custom_fields']:
    if f['gid'] == '$SPENT_DEV_HRS_FIELD':
        spent_dev = f.get('number_value')
    elif f['gid'] == '$EST_REVIEW_HRS_FIELD':
        est_review = f.get('number_value')
if est_review is not None:
    print('>> Est. Review Hrs: already set (' + str(est_review) + ')')
elif spent_dev is None:
    print('>> Est. Review Hrs: skipped (no Spent Dev Hrs)')
else:
    val = max(round(spent_dev * 0.1, 1), 0.1)
    print(f'SET_EST_REVIEW={val}')
" 2>/dev/null | while IFS= read -r line; do
  if [[ "$line" == SET_EST_REVIEW=* ]]; then
    VAL="${line#SET_EST_REVIEW=}"
    curl -s -X PUT "https://app.asana.com/api/1.0/tasks/$TASK_GID" \
      -H "Authorization: Bearer $ASANA_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"data\":{\"custom_fields\":{\"$EST_REVIEW_HRS_FIELD\":$VAL}}}" > /dev/null 2>&1 || true
    echo ">> Est. Review Hrs: set to $VAL (10% of Spent Dev Hrs)"
  else
    echo "$line"
  fi
done || true
