#!/usr/bin/env bash
# github-pr-activity.sh — Fetch GitHub PR activity for a given day.
# Detects two categories:
#   1. Addressed review comments: user's own PRs where human reviews existed
#      and the user pushed commits on the target date
#   2. Submitted reviews: PRs authored by others that the user reviewed on
#      the target date
#
# Usage:
#   github-pr-activity.sh [--date YYYY-MM-DD]
#
# Requires: gh CLI authenticated
#
# Output: JSON { date, username, addressed: [...], reviewed: [...] }
set -euo pipefail

TARGET_DATE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --date) TARGET_DATE="$2"; shift 2 ;;
    *) echo "Unknown: $1" >&2; exit 1 ;;
  esac
done

if ! command -v gh &>/dev/null; then
  echo "Error: gh CLI not installed" >&2; exit 1
fi
if ! gh auth status &>/dev/null 2>&1; then
  echo "PROMPT_GH_AUTH" >&2; exit 2
fi

USERNAME=$(gh api user --jq '.login')

export TARGET_DATE USERNAME

python3 - << 'PYEOF'
import json, os, re, subprocess, sys
from datetime import date, timedelta

USERNAME = os.environ["USERNAME"]
TARGET_DATE_STR = os.environ.get("TARGET_DATE", "")

if TARGET_DATE_STR:
    target = date.fromisoformat(TARGET_DATE_STR)
else:
    today = date.today()
    if today.weekday() == 0:
        target = today - timedelta(days=3)
    else:
        target = today - timedelta(days=1)
    TARGET_DATE_STR = target.isoformat()


def gh_graphql(query, variables):
    args = ["gh", "api", "graphql", "-f", f"query={query}"]
    for k, v in variables.items():
        args.extend(["-f", f"{k}={v}"])
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"GH_ERROR: {result.stderr[:300]}", file=sys.stderr)
        return {"data": {"search": {"nodes": []}}}
    parsed = json.loads(result.stdout)
    if "errors" in parsed:
        print(f"GQL_ERROR: {json.dumps(parsed['errors'][:2])}", file=sys.stderr)
    return parsed


def extract_asana_gid(body):
    if not body:
        return None
    m = re.search(r'asana\.com/\S*/(\d{10,})', body)
    return m.group(1) if m else None


# --- Query 1: User's own PRs updated recently (check for addressed comments) ---
QUERY_AUTHORED = """
query($search: String!) {
  search(query: $search, type: ISSUE, first: 50) {
    nodes {
      ... on PullRequest {
        number
        title
        url
        body
        repository { nameWithOwner }
        reviews(last: 30) {
          nodes {
            author { login }
            state
            submittedAt
          }
        }
        commits(last: 30) {
          nodes {
            commit {
              committedDate
              author { user { login } }
            }
          }
        }
      }
    }
  }
}
"""

search_authored = f"is:pr author:{USERNAME} updated:>={TARGET_DATE_STR} sort:updated"
authored_raw = gh_graphql(QUERY_AUTHORED, {"search": search_authored})

addressed = []
for node in authored_raw.get("data", {}).get("search", {}).get("nodes", []):
    if not node or "number" not in node:
        continue

    has_human_review = False
    for r in (node.get("reviews") or {}).get("nodes", []):
        if not r or not r.get("author"):
            continue
        reviewer = r["author"].get("login", "")
        if reviewer == USERNAME or "[bot]" in reviewer:
            continue
        if r.get("state") in ("CHANGES_REQUESTED", "COMMENTED"):
            has_human_review = True
            break

    if not has_human_review:
        continue

    has_commit_on_date = False
    for c in (node.get("commits") or {}).get("nodes", []):
        commit = (c or {}).get("commit", {})
        committed = (commit.get("committedDate") or "")[:10]
        commit_user = ((commit.get("author") or {}).get("user") or {}).get("login", "")
        if committed == TARGET_DATE_STR and commit_user == USERNAME:
            has_commit_on_date = True
            break

    if has_commit_on_date:
        addressed.append({
            "pr_number": node["number"],
            "pr_title": node["title"],
            "pr_url": node["url"],
            "repo": node["repository"]["nameWithOwner"],
            "asana_gid": extract_asana_gid(node.get("body")),
        })

# --- Query 2: PRs reviewed by user (not authored by user) ---
QUERY_REVIEWED = """
query($search: String!) {
  search(query: $search, type: ISSUE, first: 50) {
    nodes {
      ... on PullRequest {
        number
        title
        url
        body
        repository { nameWithOwner }
        reviews(last: 30) {
          nodes {
            author { login }
            state
            submittedAt
          }
        }
      }
    }
  }
}
"""

search_reviewed = f"is:pr reviewed-by:{USERNAME} -author:{USERNAME} updated:>={TARGET_DATE_STR} sort:updated"
reviewed_raw = gh_graphql(QUERY_REVIEWED, {"search": search_reviewed})

reviewed = []
for node in reviewed_raw.get("data", {}).get("search", {}).get("nodes", []):
    if not node or "number" not in node:
        continue

    review_state = None
    for r in (node.get("reviews") or {}).get("nodes", []):
        if not r or not r.get("author"):
            continue
        if r["author"].get("login") != USERNAME:
            continue
        submitted = (r.get("submittedAt") or "")[:10]
        if submitted == TARGET_DATE_STR:
            review_state = r.get("state", "COMMENTED")
            break

    if review_state:
        reviewed.append({
            "pr_number": node["number"],
            "pr_title": node["title"],
            "pr_url": node["url"],
            "repo": node["repository"]["nameWithOwner"],
            "asana_gid": extract_asana_gid(node.get("body")),
            "review_state": review_state,
        })

print(json.dumps({
    "date": TARGET_DATE_STR,
    "username": USERNAME,
    "addressed": addressed,
    "reviewed": reviewed,
}, indent=2))
PYEOF
