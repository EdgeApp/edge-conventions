#!/usr/bin/env bash
# pr-address.sh
# Companion script for pr-address.md
# Handles deterministic operations: comment fetching, replies, thread resolution, autosquash.
#
# Subcommands:
#   fetch          --owner <o> --repo <r> --pr <n>         Fetch all unresolved feedback via GraphQL
#   fetch-thread   --owner <o> --repo <r> --pr <n> --thread-id <id>
#   reply          --owner <o> --repo <r> --pr <n> --comment-id <id> --body <text>
#   resolve-thread --thread-id <node_id>                   Mark inline thread as resolved (GraphQL)
#   mark-addressed --owner <o> --repo <r> --pr <n> --type <review|comment> --target-id <id> --body <text>
#   resolve-id     --owner <o> --repo <r> --pr <n> --node-id <id>
#   headline       --owner <o> --repo <r> --sha <sha>
#   fetch-pr-body  --owner <o> --repo <r> --pr <n>         Fetch current PR body → /tmp/pr-body.md
#   autosquash                                             Rebase --autosquash from merge-base
#
# Exit codes: 0 = success, 1 = error, 2 = needs user input (e.g. gh not authenticated)
set -euo pipefail

CMD="${1:-}"
shift || true

OWNER="" REPO="" PR="" COMMENT_ID="" NODE_ID="" BODY="" SHA="" THREAD_ID="" TARGET_TYPE="" TARGET_ID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner) OWNER="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --pr) PR="$2"; shift 2 ;;
    --comment-id) COMMENT_ID="$2"; shift 2 ;;
    --node-id) NODE_ID="$2"; shift 2 ;;
    --body) BODY="$2"; shift 2 ;;
    --sha) SHA="$2"; shift 2 ;;
    --thread-id) THREAD_ID="$2"; shift 2 ;;
    --type) TARGET_TYPE="$2"; shift 2 ;;
    --target-id) TARGET_ID="$2"; shift 2 ;;
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
  fetch)
    require_gh
    if [[ -z "$OWNER" || -z "$REPO" || -z "$PR" ]]; then
      echo "Error: --owner, --repo, --pr required" >&2; exit 1
    fi

    gh api graphql \
      -f query='query($owner: String!, $repo: String!, $number: Int!) {
        repository(owner: $owner, name: $repo) {
          pullRequest(number: $number) {
            author { login }
            headRefName
            baseRefName
            reviewThreads(first: 100) {
              nodes {
                id
                isResolved
                comments(first: 50) {
                  nodes {
                    databaseId
                    createdAt
                    author { login }
                    path
                    line
                    body
                  }
                }
              }
            }
            reviews(last: 50) {
              nodes {
                databaseId
                author { login }
                state
                body
                submittedAt
              }
            }
            comments(last: 50) {
              nodes {
                databaseId
                createdAt
                author { login }
                body
              }
            }
          }
        }
      }' \
      -f owner="$OWNER" -f repo="$REPO" -F number="$PR" \
    | GH_USER=$(gh api user --jq '.login') node -e "
      const fs = require('fs')
      const data = JSON.parse(fs.readFileSync('/dev/stdin', 'utf8'))
      const pr = data.data.repository.pullRequest
      const prAuthor = pr.author?.login
      const currentUser = process.env.GH_USER

      const addressedIds = new Set()
      for (const c of pr.comments.nodes) {
        for (const m of (c.body || '').matchAll(/<!-- addressed:(?:review|comment):(\d+) -->/g)) {
          addressedIds.add(Number(m[1]))
        }
      }

      const isBot = u => !u || u.includes('[bot]') || u === 'cursor'
      const isAutomatedReviewer = u => isBot(u) || u === 'chatgpt-codex-connector'

      const threads = pr.reviewThreads.nodes
        .filter(t => !t.isResolved)
        .map(t => ({
          threadId: t.id,
          path: t.comments.nodes[0]?.path,
          line: t.comments.nodes[0]?.line,
          comments: t.comments.nodes.map(c => ({
            id: c.databaseId,
            user: c.author?.login,
            body: c.body,
            createdAt: c.createdAt
          }))
        }))

      // Check if any human (non-bot, non-automated, non-currentUser) reviewer has commented
      // prAuthor CAN be an external human reviewer if they're not currentUser
      const humanCommenters = new Set()
      for (const t of threads) {
        for (const c of t.comments) {
          if (c.user && !isAutomatedReviewer(c.user) && c.user !== currentUser) {
            humanCommenters.add(c.user)
          }
        }
      }

      const latestByUser = {}
      for (const r of pr.reviews.nodes) {
        const user = r.author?.login
        if (!user || user === prAuthor || r.state === 'PENDING' || isBot(user)) continue
        const prev = latestByUser[user]
        if (!prev || new Date(r.submittedAt) > new Date(prev.submittedAt)) {
          latestByUser[user] = r
        }
        if (!isAutomatedReviewer(user) && user !== currentUser) {
          humanCommenters.add(user)
        }
      }
      const reviewBodies = Object.entries(latestByUser)
        .filter(([, r]) => r.body?.trim() && !addressedIds.has(r.databaseId))
        .map(([user, r]) => ({
          reviewId: r.databaseId, user, state: r.state,
          body: r.body, submittedAt: r.submittedAt
        }))

      const topLevel = pr.comments.nodes.filter(c => {
        const user = c.author?.login
        if (!user || user === prAuthor || isBot(user)) return false
        if ((c.body || '').includes('<!-- addressed:')) return false
        if (!isAutomatedReviewer(user) && user !== currentUser) {
          humanCommenters.add(user)
        }
        return !addressedIds.has(c.databaseId)
      }).map(c => ({
        id: c.databaseId, user: c.author?.login,
        body: c.body, createdAt: c.createdAt
      }))

      console.log(JSON.stringify({
        prAuthor, currentUser, headRef: pr.headRefName, baseRef: pr.baseRefName,
        hasHumanReviewers: humanCommenters.size > 0,
        humanReviewers: Array.from(humanCommenters),
        threads, reviewBodies, topLevel
      }, null, 2))
    "
    ;;

  fetch-thread)
    require_gh
    if [[ -z "$OWNER" || -z "$REPO" || -z "$PR" || -z "$THREAD_ID" ]]; then
      echo "Error: --owner, --repo, --pr, --thread-id required" >&2; exit 1
    fi

    gh api graphql \
      -f query='query($owner: String!, $repo: String!, $number: Int!) {
        repository(owner: $owner, name: $repo) {
          pullRequest(number: $number) {
            reviewThreads(first: 100) {
              nodes {
                id
                isResolved
                comments(first: 50) {
                  nodes {
                    databaseId
                    createdAt
                    author { login }
                    path
                    line
                    body
                  }
                }
              }
            }
          }
        }
      }' \
      -f owner="$OWNER" -f repo="$REPO" -F number="$PR" \
    | GH_THREAD_ID="$THREAD_ID" node -e "
      const fs = require('fs')
      const data = JSON.parse(fs.readFileSync('/dev/stdin', 'utf8'))
      const threads = data.data.repository.pullRequest.reviewThreads.nodes
      const thread = threads.find(item => item.id === process.env.GH_THREAD_ID)
      if (thread == null) {
        console.error('Thread not found: ' + process.env.GH_THREAD_ID)
        process.exit(1)
      }

      console.log(JSON.stringify({
        threadId: thread.id,
        isResolved: thread.isResolved,
        path: thread.comments.nodes[0]?.path ?? null,
        line: thread.comments.nodes[0]?.line ?? null,
        comments: thread.comments.nodes.map(comment => ({
          id: comment.databaseId,
          user: comment.author?.login ?? null,
          body: comment.body,
          createdAt: comment.createdAt
        }))
      }, null, 2))
    "
    ;;

  reply)
    require_gh
    if [[ -z "$OWNER" || -z "$REPO" || -z "$PR" || -z "$COMMENT_ID" || -z "$BODY" ]]; then
      echo "Error: --owner, --repo, --pr, --comment-id, --body required" >&2; exit 1
    fi
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

  resolve-thread)
    require_gh
    if [[ -z "$THREAD_ID" ]]; then
      echo "Error: --thread-id required" >&2; exit 1
    fi
    RESULT=$(gh api graphql \
      -f query='mutation($id: ID!) { resolveReviewThread(input: {threadId: $id}) { thread { id isResolved } } }' \
      -f id="$THREAD_ID")
    RESOLVED=$(echo "$RESULT" | jq -r '.data.resolveReviewThread.thread.isResolved // empty')
    if [[ "$RESOLVED" == "true" ]]; then
      echo "resolved: $THREAD_ID"
    else
      echo "Resolve failed: $RESULT" >&2; exit 1
    fi
    ;;

  mark-addressed)
    require_gh
    if [[ -z "$OWNER" || -z "$REPO" || -z "$PR" || -z "$TARGET_TYPE" || -z "$TARGET_ID" || -z "$BODY" ]]; then
      echo "Error: --owner, --repo, --pr, --type, --target-id, --body required" >&2; exit 1
    fi
    MARKER="<!-- addressed:${TARGET_TYPE}:${TARGET_ID} -->"
    FULL_BODY="${BODY} ${MARKER}"
    RESULT=$(echo '{}' | jq --arg body "$FULL_BODY" '{body: $body}' | \
      gh api "repos/$OWNER/$REPO/issues/$PR/comments" -X POST --input -)
    ID=$(echo "$RESULT" | jq -r '.id // empty')
    if [[ -n "$ID" ]]; then
      echo "marked: $ID ($MARKER)"
    else
      echo "Mark failed: $RESULT" >&2; exit 1
    fi
    ;;

  resolve-id)
    require_gh
    if [[ -z "$OWNER" || -z "$REPO" || -z "$PR" || -z "$NODE_ID" ]]; then
      echo "Error: --owner, --repo, --pr, --node-id required" >&2; exit 1
    fi
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
    if [[ -z "$OWNER" || -z "$REPO" || -z "$SHA" ]]; then
      echo "Error: --owner, --repo, --sha required" >&2; exit 1
    fi
    gh api "repos/$OWNER/$REPO/commits/$SHA" --jq '.commit.message | split("\n") | .[0]'
    ;;

  fetch-pr-body)
    require_gh
    if [[ -z "$OWNER" || -z "$REPO" || -z "$PR" ]]; then
      echo "Error: --owner, --repo, --pr required" >&2; exit 1
    fi
    BODY=$(gh api "repos/$OWNER/$REPO/pulls/$PR" --jq '.body // ""')
    echo "$BODY" > /tmp/pr-body.md
    echo ">> Wrote PR body to /tmp/pr-body.md ($(wc -c < /tmp/pr-body.md | tr -d ' ') bytes)"
    ;;

  autosquash)
    DEFAULT_UPSTREAM=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null \
      || echo "origin/$(git remote show origin | sed -n '/HEAD branch/s/.*: //p')")
    BASE=$(git merge-base "$DEFAULT_UPSTREAM" HEAD)
    GIT_EDITOR=true git -c sequence.editor=: rebase -i "$BASE" --autosquash
    echo ">> Autosquash complete"
    ;;

  *)
    echo "Usage: pr-address.sh {fetch|fetch-thread|reply|resolve-thread|mark-addressed|resolve-id|headline|fetch-pr-body|autosquash} [args]" >&2
    exit 1
    ;;
esac
