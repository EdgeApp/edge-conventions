#!/usr/bin/env bash
# pr-address.sh
# Companion script for pr-address.md
# Handles deterministic operations: context gathering, comment replies, autosquash.
#
# Subcommands:
#   context    --pr-dir <dir>                          Read PR snapshot
#   fetch      --owner <o> --repo <r> --pr <n>         Fetch live comments from GitHub API
#   reply      --owner <o> --repo <r> --pr <n> --comment-id <id> --body <text>
#   resolve-id --owner <o> --repo <r> --pr <n> --node-id <id>
#   headline   --owner <o> --repo <r> --sha <sha>
#   autosquash                                         Rebase --autosquash from merge-base
#
# Exit codes: 0 = success, 1 = error, 2 = needs user input (e.g. gh not authenticated)
set -euo pipefail

CMD="${1:-}"
shift || true

OWNER="" REPO="" PR="" PR_DIR="" COMMENT_ID="" NODE_ID="" BODY="" SHA=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner) OWNER="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --pr) PR="$2"; shift 2 ;;
    --pr-dir) PR_DIR="$2"; shift 2 ;;
    --comment-id) COMMENT_ID="$2"; shift 2 ;;
    --node-id) NODE_ID="$2"; shift 2 ;;
    --body) BODY="$2"; shift 2 ;;
    --sha) SHA="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

require_gh() {
  if ! command -v gh &>/dev/null; then
    echo "PROMPT_GH_INSTALL" >&2; exit 2
  fi
  if ! gh auth status &>/dev/null 2>&1; then
    echo "PROMPT_GH_AUTH" >&2; exit 2
  fi
}

case "$CMD" in
  context)
    if [[ -z "$PR_DIR" ]]; then
      echo "Error: --pr-dir required" >&2; exit 1
    fi
    node -e "
      const s = require(process.argv[1] + '/summary.json')
      const c = require(process.argv[1] + '/comments.json')
      console.log(JSON.stringify({
        owner: s.owner, repo: s.repo, prNumber: s.prNumber,
        headRef: s.headRef, baseRef: s.baseRef,
        files: s.files?.length,
        unresolvedThreads: s.unresolvedCommentThreads,
        fetchedAt: c.fetchedAt,
        totalThreads: c.totalThreads,
        unresolved: c.unresolvedThreads,
        resolved: c.resolvedThreads,
        threadsByFile: c.threadsByFile
      }, null, 2))
    " "$PR_DIR"
    ;;

  fetch)
    require_gh
    INLINE=$(gh api "repos/$OWNER/$REPO/pulls/$PR/comments" --paginate)
    TOP=$(gh api "repos/$OWNER/$REPO/issues/$PR/comments" --paginate)
    node -e "
      const inline = JSON.parse(process.argv[1])
      const top = JSON.parse(process.argv[2])
      console.log(JSON.stringify({
        inline_count: inline.length, top_count: top.length,
        inline: inline.map(c => ({
          id: c.id, node_id: c.node_id, user: c.user?.login,
          path: c.path, line: c.line, body: c.body,
          commit_id: c.commit_id, created_at: c.created_at
        })),
        top: top.map(c => ({
          id: c.id, user: c.user?.login,
          body: c.body, created_at: c.created_at
        }))
      }, null, 2))
    " "$INLINE" "$TOP"
    ;;

  reply)
    require_gh
    RESULT=$(echo '{}' | jq --arg body "$BODY" '{body: $body}' | \
      gh api "repos/$OWNER/$REPO/pulls/$PR/comments/$COMMENT_ID/replies" \
        -X POST --input -)
    ID=$(echo "$RESULT" | jq -r '.id // empty')
    if [[ -n "$ID" ]]; then
      echo "replied: $ID"
    else
      echo "Reply failed: $RESULT" >&2; exit 1
    fi
    ;;

  resolve-id)
    require_gh
    RESULT=$(gh api "repos/$OWNER/$REPO/pulls/$PR/comments" --paginate \
      --jq ".[] | select(.node_id == \"$NODE_ID\") | .id")
    if [[ -n "$RESULT" ]]; then
      echo "$RESULT"
    else
      echo "Comment not found for node_id: $NODE_ID" >&2; exit 1
    fi
    ;;

  headline)
    require_gh
    gh api "repos/$OWNER/$REPO/commits/$SHA" --jq '.commit.message | split("\n") | .[0]'
    ;;

  autosquash)
    DEFAULT_UPSTREAM=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null \
      || echo "origin/$(git remote show origin | sed -n '/HEAD branch/s/.*: //p')")
    BASE=$(git merge-base "$DEFAULT_UPSTREAM" HEAD)
    GIT_EDITOR=true git -c sequence.editor=: rebase -i "$BASE" --autosquash
    echo ">> Autosquash complete"
    ;;

  *)
    echo "Usage: pr-address.sh {context|fetch|reply|resolve-id|headline|autosquash} [args]" >&2
    exit 1
    ;;
esac
