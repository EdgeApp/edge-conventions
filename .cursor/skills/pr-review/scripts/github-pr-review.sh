#!/usr/bin/env bash
# github-pr-review.sh — Fetch PR review context and submit reviews via gh CLI.
#
# Subcommands:
#   context  [--pr <number>] [--owner <o>] [--repo <r>]   Fetch PR metadata + files + existing reviews
#   submit   --pr <n> --owner <o> --repo <r> --sha <sha>  Post review (JSON on stdin)
#
# The `context` subcommand auto-detects the PR from the current branch if --pr is omitted.
# Total API calls: 2 (gh pr view + gh api for file patches).
#
# Exit codes: 0 = success, 1 = error, 2 = needs user input (e.g. gh not authenticated)
set -euo pipefail

CMD="${1:-}"
shift || true

OWNER="" REPO="" PR="" SHA=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner) OWNER="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --pr) PR="$2"; shift 2 ;;
    --sha) SHA="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

require_gh() {
  if ! command -v gh &>/dev/null; then
    echo "Error: gh CLI not installed." >&2
    exit 1
  fi
  if ! gh auth status &>/dev/null 2>&1; then
    echo "PROMPT_GH_AUTH" >&2
    exit 2
  fi
}

case "$CMD" in
  context)
    require_gh

    # --- Call 1: PR metadata + reviews via gh pr view ---
    VIEW_ARGS=()
    [[ -n "$PR" ]] && VIEW_ARGS+=("$PR")
    [[ -n "$OWNER" && -n "$REPO" ]] && VIEW_ARGS+=("--repo" "$OWNER/$REPO")

    META=$(gh pr view ${VIEW_ARGS[@]+"${VIEW_ARGS[@]}"} \
      --json number,title,url,headRefName,headRefOid,baseRefName,reviews 2>&1) || {
      echo "Error: Failed to fetch PR. Output: $META" >&2
      exit 1
    }

    # Parse owner/repo/number from the PR URL
    NUMBER=$(echo "$META" | jq -r '.number')
    URL=$(echo "$META" | jq -r '.url')
    _OWNER=$(echo "$URL" | cut -d/ -f4)
    _REPO=$(echo "$URL" | cut -d/ -f5)

    # --- Call 2: Changed files with patches (REST — GraphQL doesn't expose patches) ---
    FILES=$(gh api "repos/$_OWNER/$_REPO/pulls/$NUMBER/files" --paginate 2>&1) || {
      echo "Error: Failed to fetch PR files. Output: $FILES" >&2
      exit 1
    }

    # Merge into single structured JSON output
    jq -n \
      --argjson meta "$META" \
      --argjson files "$FILES" \
      '{
        number: $meta.number,
        title: $meta.title,
        url: $meta.url,
        headRef: $meta.headRefName,
        baseRef: $meta.baseRefName,
        headSha: $meta.headRefOid,
        reviews: [($meta.reviews // [])[] | {user: .author.login, state: .state, body: .body}],
        files: [$files[] | {path: .filename, status: .status, additions: .additions, deletions: .deletions, patch: .patch}]
      }'
    ;;

  submit)
    require_gh

    if [[ -z "$PR" || -z "$OWNER" || -z "$REPO" || -z "$SHA" ]]; then
      echo "Error: --pr, --owner, --repo, --sha required for submit" >&2
      exit 1
    fi

    # Read review JSON from stdin: { event, body, comments: [{path, line, body, start_line?, side?}] }
    # Inject commit_id from --sha and POST to reviews endpoint
    jq --arg sha "$SHA" '. + {commit_id: $sha}' | \
      gh api "repos/$OWNER/$REPO/pulls/$PR/reviews" -X POST --input - | \
      jq '{id: .id, state: .state, url: .html_url}'
    ;;

  *)
    echo "Usage: github-pr-review.sh {context|submit} [args]" >&2
    exit 1
    ;;
esac
