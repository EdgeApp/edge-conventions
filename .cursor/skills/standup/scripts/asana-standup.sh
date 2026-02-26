#!/usr/bin/env bash
# asana-standup.sh — Fetch Asana tasks the user interacted with on a given day.
# Outputs structured JSON for standup document generation.
#
# Usage:
#   asana-standup.sh [--date YYYY-MM-DD]
#
# If --date is omitted, defaults to yesterday (or Friday if today is Monday).
#
# Requires env var: ASANA_TOKEN
#
# Output: JSON { date, day_label, user_name, task_count, candidate_count,
#   tasks: [...], handoffs: [...], active_tasks: [...] }
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

TARGET_DATE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --date) TARGET_DATE="$2"; shift 2 ;;
    *) echo "Unknown: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "${ASANA_TOKEN:-}" ]]; then
  echo "Error: ASANA_TOKEN not set" >&2
  exit 1
fi

USER_INFO=$("$SCRIPT_DIR/../../asana-whoami.sh" --name)
USER_GID=$(echo "$USER_INFO" | awk '{print $1}')
USER_NAME=$(echo "$USER_INFO" | cut -d' ' -f2-)

CACHE_KEY=$(echo "$ASANA_TOKEN" | shasum -a 256 | cut -c1-16)
WORKSPACE_CACHE="/tmp/asana-workspace-$CACHE_KEY.txt"
if [[ -f "$WORKSPACE_CACHE" ]]; then
  WORKSPACE_GID=$(cat "$WORKSPACE_CACHE")
else
  WORKSPACE_GID=$(curl -s "https://app.asana.com/api/1.0/users/me?opt_fields=workspaces" \
    -H "Authorization: Bearer $ASANA_TOKEN" | \
    python3 -c "import sys,json; print(json.load(sys.stdin)['data']['workspaces'][0]['gid'])")
  echo "$WORKSPACE_GID" > "$WORKSPACE_CACHE"
fi

export ASANA_TOKEN USER_GID USER_NAME WORKSPACE_GID TARGET_DATE

python3 - << 'PYEOF'
import json, os, re, sys, urllib.request, urllib.parse, urllib.error
from datetime import date, timedelta

API = "https://app.asana.com/api/1.0"
TOKEN = os.environ["ASANA_TOKEN"]
USER_GID = os.environ["USER_GID"]
USER_NAME = os.environ["USER_NAME"]
WORKSPACE = os.environ["WORKSPACE_GID"]
TARGET_DATE_STR = os.environ.get("TARGET_DATE", "")

STATUS_FIELD_GID = "1190660107346181"


def api_get(path, params=None):
    url = f"{API}{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params, doseq=True)
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {TOKEN}"})
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        body = e.read().decode() if e.fp else ""
        print(f"API_ERROR: {e.code} {path} {body[:200]}", file=sys.stderr)
        return {"data": []}


# --- Date calculation ---
if TARGET_DATE_STR:
    target = date.fromisoformat(TARGET_DATE_STR)
    day_label = target.strftime("%A")
else:
    today = date.today()
    if today.weekday() == 0:  # Monday
        target = today - timedelta(days=3)
        day_label = "Friday"
    else:
        target = today - timedelta(days=1)
        day_label = "yesterday"
    TARGET_DATE_STR = target.isoformat()

# ±1 day buffer handles modified_on drift (task modified yesterday + today
# has modified_on=today, so we need the window slightly wider than exact day).
window_start = (target - timedelta(days=1)).isoformat()
window_end = (target + timedelta(days=1)).isoformat()

# --- Search queries ---
search_path = f"/workspaces/{WORKSPACE}/tasks/search"
opt = "name,assignee.name,memberships.project.name,custom_fields.gid,custom_fields.display_value,permalink_url"

search_filters = [
    {"assignee.any": USER_GID},
    {"assigned_by.any": USER_GID},
]

tasks_by_gid = {}
for extra in search_filters:
    params = {
        "modified_on.after": window_start,
        "modified_on.before": window_end,
        "opt_fields": opt,
        "limit": "100",
        **extra,
    }
    result = api_get(search_path, params)
    for t in result.get("data", []):
        if t["gid"] not in tasks_by_gid:
            tasks_by_gid[t["gid"]] = t

print(f"Found {len(tasks_by_gid)} candidate tasks", file=sys.stderr)

candidate_count = len(tasks_by_gid)

# --- Fetch stories per task, categorize user actions ---
output_tasks = []
handoffs = []

for gid, task in tasks_by_gid.items():
    stories = api_get(f"/tasks/{gid}/stories", {
        "opt_fields": "resource_subtype,text,created_by.gid,created_by.name,created_at",
        "limit": "100",
    })

    story_list = stories.get("data", [])

    # Pass 1: Detect status transitions to "Review Needed" (any author)
    pr_action = None
    for s in story_list:
        created_at = s.get("created_at", "")[:10]
        if created_at != TARGET_DATE_STR:
            continue
        if s.get("resource_subtype") == "comment_added":
            continue
        text_lc = ((s.get("text") or "")).lower()
        if re.search(r"to\s+'?review needed", text_lc):
            if re.search(r"from\s+'?changes needed", text_lc):
                pr_action = {"type": "addressed_pr_comments", "detail": ""}
            else:
                pr_action = {"type": "prd", "detail": ""}

    # Pass 2: User's own actions (comments, moves, etc.)
    user_actions = []
    for s in story_list:
        created_at = s.get("created_at", "")[:10]
        if created_at != TARGET_DATE_STR:
            continue
        if (s.get("created_by") or {}).get("gid") != USER_GID:
            continue

        subtype = s.get("resource_subtype", "")
        text = (s.get("text") or "").strip()
        short = (text[:150] + "...") if len(text) > 150 else text

        if subtype == "comment_added":
            user_actions.append({"type": "commented", "detail": short})
        elif subtype == "assigned":
            m = re.search(r'assigned to (.+)$', text)
            target_name = m.group(1).strip() if m else ""
            if target_name.lower() == "you" or target_name == USER_NAME:
                continue
            if not target_name:
                target_name = (task.get("assignee") or {}).get("name", "someone")
            handoffs.append({
                "gid": gid,
                "name": task.get("name", ""),
                "url": task.get("permalink_url", f"https://app.asana.com/0/0/{gid}/f"),
                "kind": "reassigned",
                "detail": target_name,
            })
        elif subtype == "marked_complete":
            user_actions.append({"type": "completed", "detail": short})
        elif subtype == "section_changed":
            user_actions.append({"type": "moved", "detail": short})
        elif subtype == "added_to_project":
            user_actions.append({"type": "added to project", "detail": short})

    if pr_action:
        user_actions.append(pr_action)

    if not user_actions:
        continue

    project = ""
    for m in task.get("memberships", []):
        p = (m.get("project") or {}).get("name", "")
        if p:
            project = p
            break

    status = ""
    for f in task.get("custom_fields", []):
        if f.get("gid") == STATUS_FIELD_GID:
            status = f.get("display_value") or ""
            break

    output_tasks.append({
        "gid": gid,
        "name": task.get("name", ""),
        "url": task.get("permalink_url", f"https://app.asana.com/0/0/{gid}/f"),
        "project": project,
        "status": status,
        "assignee": (task.get("assignee") or {}).get("name", ""),
        "actions": user_actions,
    })

    if "block" in status.lower():
        handoffs.append({
            "gid": gid,
            "name": task.get("name", ""),
            "url": task.get("permalink_url", f"https://app.asana.com/0/0/{gid}/f"),
            "kind": "blocker",
            "detail": f"Status: {status}",
        })

# --- Active tasks where user is involved (for debug) ---
ACTIVE_STATUSES = {"Started", "Review Needed", "Changes Needed", "Publish Needed", "Verification Needed"}
IMPLEMENTOR_FIELD = "1203334386796983"
REVIEWER_FIELD = "1203334388004673"

active_window_start = (target - timedelta(days=90)).isoformat()
active_result = api_get(search_path, {
    "followers.any": USER_GID,
    f"custom_fields.{STATUS_FIELD_GID}.is_set": "true",
    "modified_on.after": active_window_start,
    "opt_fields": "name,assignee.name,assignee.gid,custom_fields.gid,custom_fields.display_value,custom_fields.people_value.gid,permalink_url",
    "limit": "100",
})

active_tasks = []
seen_gids = set()
for t in active_result.get("data", []):
    if t["gid"] in seen_gids:
        continue
    seen_gids.add(t["gid"])
    status_name = ""
    is_implementor = False
    is_reviewer = False
    for f in t.get("custom_fields", []):
        fgid = f.get("gid", "")
        if fgid == STATUS_FIELD_GID:
            status_name = f.get("display_value") or ""
        elif fgid == IMPLEMENTOR_FIELD:
            for p in (f.get("people_value") or []):
                if (p or {}).get("gid") == USER_GID:
                    is_implementor = True
        elif fgid == REVIEWER_FIELD:
            for p in (f.get("people_value") or []):
                if (p or {}).get("gid") == USER_GID:
                    is_reviewer = True
    if status_name not in ACTIVE_STATUSES:
        continue
    assignee_gid = ((t.get("assignee") or {}).get("gid", ""))
    if assignee_gid != USER_GID and not is_implementor and not is_reviewer:
        continue
    role = "assignee" if assignee_gid == USER_GID else ("implementor" if is_implementor else "reviewer")
    active_tasks.append({
        "name": t.get("name", ""),
        "url": t.get("permalink_url", f"https://app.asana.com/0/0/{t['gid']}/f"),
        "status": status_name,
        "assignee": (t.get("assignee") or {}).get("name", ""),
        "role": role,
    })

print(json.dumps({
    "date": TARGET_DATE_STR,
    "day_label": day_label,
    "user_name": USER_NAME,
    "task_count": len(output_tasks),
    "candidate_count": candidate_count,
    "tasks": output_tasks,
    "handoffs": handoffs,
    "active_tasks": active_tasks,
}, indent=2))
PYEOF
