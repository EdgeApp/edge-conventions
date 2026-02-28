#!/usr/bin/env bash
# asana-create-dep-task.sh
# Create a dependent Asana task that blocks a parent task.
# Checks for existing dependencies first to avoid duplicates.
#
# Usage:
#   asana-create-dep-task.sh --parent <parent_gid> --name "task name" [--notes "description"] [--assignee <user_gid>]
#
# If --assignee is omitted, the task is assigned to the current user
# (resolved via asana-whoami.sh).
#
# Requires env var: ASANA_TOKEN
#
# Output:
#   TASK_GID: <gid>
#   TASK_URL: <url>
#   CREATED: true|false (false if task already existed)
#   ASSIGNED_TO: <user_gid>
#   FIELDS_SET: priority=<val>, status=<val>, planned=<val>, reviewer=<name>, implementor=<name>
#   DEPENDENCY_SET: <new_gid> blocks <parent_gid>
#
# Exit codes: 0 = success, 1 = error
set -euo pipefail

PARENT_GID=""
TASK_NAME=""
TASK_NOTES=""
ASSIGNEE_GID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --parent) PARENT_GID="$2"; shift 2 ;;
    --name) TASK_NAME="$2"; shift 2 ;;
    --notes) TASK_NOTES="$2"; shift 2 ;;
    --assignee) ASSIGNEE_GID="$2"; shift 2 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$PARENT_GID" || -z "$TASK_NAME" ]]; then
  echo "Usage: asana-create-dep-task.sh --parent <gid> --name <name> [--notes <desc>] [--assignee <gid>]" >&2
  exit 1
fi

if [[ -z "${ASANA_TOKEN:-}" ]]; then
  echo "Error: ASANA_TOKEN not set" >&2
  exit 1
fi

API="https://app.asana.com/api/1.0"
AUTH="Authorization: Bearer $ASANA_TOKEN"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Auto-resolve current user GID (used for assignee and implementor)
CURRENT_USER_GID=$("$SCRIPT_DIR/../../asana-whoami.sh" 2>/dev/null || true)

# Auto-resolve assignee to current user if not provided
if [[ -z "$ASSIGNEE_GID" ]]; then
  ASSIGNEE_GID="$CURRENT_USER_GID"
fi

# Phase 1: Check if a dependency with a matching name already exists
existing=$(curl -s "$API/tasks/$PARENT_GID/dependencies?opt_fields=name&limit=100" \
  -H "$AUTH" | python3 -c "
import sys, json
data = json.load(sys.stdin).get('data', [])
target = '''$TASK_NAME'''
for dep in data:
    if dep.get('name', '').strip().lower() == target.strip().lower():
        print(dep['gid'])
        sys.exit(0)
print('')
")

if [[ -n "$existing" ]]; then
  echo "TASK_GID: $existing"
  echo "TASK_URL: https://app.asana.com/0/0/$existing"
  echo "CREATED: false"
  exit 0
fi

# Phase 2: Get parent task's project and custom fields to copy
parent_info=$(curl -s "$API/tasks/$PARENT_GID?opt_fields=workspace.gid,memberships.project.gid,memberships.project.name,custom_fields.gid,custom_fields.enum_value.gid,custom_fields.enum_value.name,custom_fields.people_value.gid,custom_fields.people_value.name" \
  -H "$AUTH")

read -r WORKSPACE_GID PROJECT_GIDS PRIORITY_INFO STATUS_INFO PLANNED_INFO REVIEWER_INFO < <(echo "$parent_info" | python3 -c "
import sys, json, re
data = json.load(sys.stdin)['data']
ws = data.get('workspace', {}).get('gid', '')

# Collect all parent projects (including release-version projects like 4.46.0)
projects = []
for m in data.get('memberships', []):
    p = m.get('project', {})
    gid = p.get('gid', '')
    if gid:
        projects.append(gid)
if not projects and data.get('memberships'):
    projects.append(data['memberships'][0]['project']['gid'])
proj_str = ','.join(projects)

# Field GIDs (stable known fields)
ENUM_FIELDS = {
    '795866930204488': 'priority',
    '1190660107346181': 'status',
}
PEOPLE_FIELDS = {
    '1203334388004673': 'reviewer',
}

enum_results = {}
people_results = {}

for f in data.get('custom_fields', []):
    fgid = f['gid']
    if fgid in ENUM_FIELDS and f.get('enum_value'):
        label = ENUM_FIELDS[fgid]
        enum_results[label] = (fgid, f['enum_value']['gid'], f['enum_value'].get('name', ''))
    # "Planned" is workspace-specific, so detect by field name:
    if f.get('name') == 'Planned' and f.get('enum_value'):
        enum_results['planned'] = (
            fgid,
            f['enum_value']['gid'],
            f['enum_value'].get('name', '')
        )
    if fgid in PEOPLE_FIELDS:
        label = PEOPLE_FIELDS[fgid]
        pv = f.get('people_value', [])
        if pv:
            people_results[label] = (fgid, pv[0]['gid'], pv[0].get('name', ''))

def fmt_enum(key):
    if key in enum_results:
        return ':'.join(enum_results[key])
    return '::'

def fmt_people(key):
    if key in people_results:
        return ':'.join(people_results[key])
    return '::'

print(f\"{ws} {proj_str} {fmt_enum('priority')} {fmt_enum('status')} {fmt_enum('planned')} {fmt_people('reviewer')}\")
")

PRIORITY_FIELD=$(echo "$PRIORITY_INFO" | cut -d: -f1)
PRIORITY_ENUM=$(echo "$PRIORITY_INFO" | cut -d: -f2)
PRIORITY_NAME=$(echo "$PRIORITY_INFO" | cut -d: -f3)
STATUS_FIELD=$(echo "$STATUS_INFO" | cut -d: -f1)
STATUS_ENUM=$(echo "$STATUS_INFO" | cut -d: -f2)
STATUS_NAME=$(echo "$STATUS_INFO" | cut -d: -f3)
PLANNED_FIELD=$(echo "$PLANNED_INFO" | cut -d: -f1)
PLANNED_ENUM=$(echo "$PLANNED_INFO" | cut -d: -f2)
PLANNED_NAME=$(echo "$PLANNED_INFO" | cut -d: -f3)
REVIEWER_FIELD=$(echo "$REVIEWER_INFO" | cut -d: -f1)
REVIEWER_GID=$(echo "$REVIEWER_INFO" | cut -d: -f2)
REVIEWER_NAME=$(echo "$REVIEWER_INFO" | cut -d: -f3)

# Auto-resolve implementor to current user
IMPLEMENTOR_FIELD="1203334386796983"
IMPLEMENTOR_GID="$CURRENT_USER_GID"
IMPLEMENTOR_NAME="current user"

# Phase 3: Create the task
NOTES_JSON=$(python3 -c "import json; print(json.dumps('''$TASK_NOTES'''))")

# Build projects list from comma-separated GIDs
IFS=',' read -ra PROJECT_ARR <<< "$PROJECT_GIDS"

new_task=$(curl -s "$API/tasks" \
  -H "$AUTH" \
  -H "Content-Type: application/json" \
  -d "$(python3 -c "
import json
projects = '''$PROJECT_GIDS'''.split(',')
assignee = '''$ASSIGNEE_GID''' or None
data = {
    'data': {
        'name': '''$TASK_NAME''',
        'notes': $NOTES_JSON,
        'projects': [p for p in projects if p],
        'workspace': '$WORKSPACE_GID'
    }
}
if assignee:
    data['data']['assignee'] = assignee
print(json.dumps(data))
")")

NEW_GID=$(echo "$new_task" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if 'errors' in data:
    print('ERROR: ' + json.dumps(data['errors']), file=sys.stderr)
    sys.exit(1)
print(data['data']['gid'])
")

if [[ -z "$NEW_GID" || "$NEW_GID" == "ERROR"* ]]; then
  echo "Error creating task" >&2
  exit 1
fi

# Phase 3b: Set copied fields via shared updater script
UPDATE_CMD=("$SCRIPT_DIR/../../asana-task-update/scripts/asana-task-update.sh" "--task" "$NEW_GID")
if [[ -n "$PRIORITY_ENUM" ]]; then
  UPDATE_CMD+=("--set-priority" "$PRIORITY_ENUM")
fi
if [[ -n "$STATUS_ENUM" ]]; then
  UPDATE_CMD+=("--set-status" "$STATUS_ENUM")
fi
if [[ -n "$PLANNED_ENUM" ]]; then
  UPDATE_CMD+=("--set-planned" "$PLANNED_ENUM")
fi
if [[ -n "$REVIEWER_GID" ]]; then
  UPDATE_CMD+=("--set-reviewer" "$REVIEWER_GID")
fi
if [[ -n "$IMPLEMENTOR_GID" ]]; then
  UPDATE_CMD+=("--set-implementor" "$IMPLEMENTOR_GID")
fi
if [[ ${#UPDATE_CMD[@]} -gt 3 ]]; then
  "${UPDATE_CMD[@]}" > /dev/null
fi

FIRST_PROJECT=$(echo "$PROJECT_GIDS" | cut -d, -f1)
echo "TASK_GID: $NEW_GID"
echo "TASK_URL: https://app.asana.com/0/$FIRST_PROJECT/$NEW_GID"
echo "CREATED: true"
[[ -n "$ASSIGNEE_GID" ]] && echo "ASSIGNED_TO: $ASSIGNEE_GID"

# Phase 4: Set as blocking dependency
curl -s -X POST "$API/tasks/$PARENT_GID/addDependencies" \
  -H "$AUTH" \
  -H "Content-Type: application/json" \
  -d "{\"data\": {\"dependencies\": [\"$NEW_GID\"]}}" > /dev/null

echo "DEPENDENCY_SET: $NEW_GID blocks $PARENT_GID"

fields_msg=""
[[ -n "$PRIORITY_NAME" ]] && fields_msg="priority=$PRIORITY_NAME"
[[ -n "$STATUS_NAME" ]] && fields_msg="${fields_msg:+$fields_msg, }status=$STATUS_NAME"
[[ -n "$PLANNED_NAME" ]] && fields_msg="${fields_msg:+$fields_msg, }planned=$PLANNED_NAME"
[[ -n "$REVIEWER_NAME" ]] && fields_msg="${fields_msg:+$fields_msg, }reviewer=$REVIEWER_NAME"
[[ -n "$IMPLEMENTOR_GID" ]] && fields_msg="${fields_msg:+$fields_msg, }implementor=$IMPLEMENTOR_NAME"
[[ -n "$fields_msg" ]] && echo "FIELDS_SET: $fields_msg"
