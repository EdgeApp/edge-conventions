#!/bin/bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: gh-review.sh <command> [args...]

Commands:
  start   <pr-number>                         Check for or create a pending review
  comment <node-id> <path> <line> <body>      Add single-line inline comment
  comment-range <node-id> <path> <start-line> <end-line> <body>
                                              Add multi-line inline comment
  summary <owner> <repo> <pr-number>          List comments in pending review
  submit  <owner> <repo> <pr-number> <db-id> <event> [body]
                                              Submit the pending review
  discard <owner> <repo> <pr-number> <db-id>  Delete the pending review

Environment:
  Requires `gh` CLI installed and authenticated.
USAGE
  exit 1
}

cmd_start() {
  local pr="${1:?PR number required}"

  local pr_json
  pr_json=$(gh pr view "$pr" --json number,headRefOid,url)

  local number head_sha owner repo url
  number=$(echo "$pr_json" | jq -r '.number')
  head_sha=$(echo "$pr_json" | jq -r '.headRefOid')
  url=$(echo "$pr_json" | jq -r '.url')
  # Parse owner and repo from URL which always points to the base repository
  owner=$(echo "$url" | sed -E 's|https://github.com/([^/]+)/([^/]+)/pull/[0-9]+.*|\1|')
  repo=$(echo "$url" | sed -E 's|https://github.com/([^/]+)/([^/]+)/pull/[0-9]+.*|\2|')

  local pending
  pending=$(gh api graphql -f query='
    query($owner: String!, $repo: String!, $pr: Int!) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $pr) {
          reviews(last: 1, states: PENDING) {
            nodes { id databaseId }
          }
        }
      }
    }
  ' -f owner="$owner" -f repo="$repo" -F pr="$number")

  local node_id db_id
  node_id=$(echo "$pending" | jq -r '.data.repository.pullRequest.reviews.nodes[0].id // empty')

  if [ -n "$node_id" ]; then
    db_id=$(echo "$pending" | jq -r '.data.repository.pullRequest.reviews.nodes[0].databaseId')
    jq -n \
      --arg status "resumed" \
      --arg node_id "$node_id" \
      --arg db_id "$db_id" \
      --arg owner "$owner" \
      --arg repo "$repo" \
      --arg number "$number" \
      --arg url "$url" \
      '{status: $status, node_id: $node_id, database_id: $db_id, owner: $owner, repo: $repo, number: $number, url: $url}'
  else
    local create_json
    create_json=$(gh api "repos/$owner/$repo/pulls/$number/reviews" \
      -f commit_id="$head_sha")

    node_id=$(echo "$create_json" | jq -r '.node_id')
    db_id=$(echo "$create_json" | jq -r '.id')
    jq -n \
      --arg status "created" \
      --arg node_id "$node_id" \
      --arg db_id "$db_id" \
      --arg owner "$owner" \
      --arg repo "$repo" \
      --arg number "$number" \
      --arg url "$url" \
      '{status: $status, node_id: $node_id, database_id: $db_id, owner: $owner, repo: $repo, number: $number, url: $url}'
  fi
}

cmd_comment() {
  local node_id="${1:?Review node ID required}"
  local path="${2:?File path required}"
  local line="${3:?Line number required}"
  local body="${4:?Comment body required}"

  gh api graphql -f query='
    mutation($reviewId: ID!, $path: String!, $line: Int!, $body: String!) {
      addPullRequestReviewThread(input: {
        pullRequestReviewId: $reviewId,
        path: $path,
        line: $line,
        body: $body
      }) {
        thread {
          id
          comments(first: 1) { nodes { body path line } }
        }
      }
    }
  ' -f reviewId="$node_id" -f path="$path" -F line="$line" -f body="$body" \
    | jq '{thread_id: .data.addPullRequestReviewThread.thread.id,
           path: .data.addPullRequestReviewThread.thread.comments.nodes[0].path,
           line: .data.addPullRequestReviewThread.thread.comments.nodes[0].line}'
}

cmd_comment_range() {
  local node_id="${1:?Review node ID required}"
  local path="${2:?File path required}"
  local start_line="${3:?Start line required}"
  local end_line="${4:?End line required}"
  local body="${5:?Comment body required}"

  gh api graphql -f query='
    mutation($reviewId: ID!, $path: String!, $line: Int!, $startLine: Int!, $body: String!) {
      addPullRequestReviewThread(input: {
        pullRequestReviewId: $reviewId,
        path: $path,
        line: $line,
        startLine: $startLine,
        body: $body
      }) {
        thread { id }
      }
    }
  ' -f reviewId="$node_id" -f path="$path" -F line="$end_line" -F startLine="$start_line" -f body="$body" \
    | jq '{thread_id: .data.addPullRequestReviewThread.thread.id}'
}

cmd_summary() {
  local owner="${1:?Owner required}"
  local repo="${2:?Repo required}"
  local pr="${3:?PR number required}"

  gh api graphql -f query='
    query($owner: String!, $repo: String!, $pr: Int!) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $pr) {
          reviews(last: 1, states: PENDING) {
            nodes {
              id
              databaseId
              body
              comments(first: 100) {
                totalCount
                nodes { body path line }
              }
            }
          }
        }
      }
    }
  ' -f owner="$owner" -f repo="$repo" -F pr="$pr" \
    | jq '{
        database_id: .data.repository.pullRequest.reviews.nodes[0].databaseId,
        total_comments: .data.repository.pullRequest.reviews.nodes[0].comments.totalCount,
        comments: [.data.repository.pullRequest.reviews.nodes[0].comments.nodes[]
                   | {path, line, body: (.body | if length > 60 then .[:60] + "..." else . end)}]
      }'
}

cmd_submit() {
  local owner="${1:?Owner required}"
  local repo="${2:?Repo required}"
  local pr="${3:?PR number required}"
  local db_id="${4:?Database ID required}"
  local event="${5:?Event required (APPROVE|COMMENT|REQUEST_CHANGES)}"
  local body="${6:-}"

  local args=(-f event="$event")
  if [ -n "$body" ]; then
    args+=(-f body="$body")
  fi

  gh api "repos/$owner/$repo/pulls/$pr/reviews/$db_id/events" "${args[@]}" \
    | jq '{id: .id, state: .state, html_url: .html_url}'
}

cmd_discard() {
  local owner="${1:?Owner required}"
  local repo="${2:?Repo required}"
  local pr="${3:?PR number required}"
  local db_id="${4:?Database ID required}"

  gh api "repos/$owner/$repo/pulls/$pr/reviews/$db_id" -X DELETE \
    | jq '{id: .id, state: "DELETED"}'
}

command="${1:-}"
shift || true

case "$command" in
  start)         cmd_start "$@" ;;
  comment)       cmd_comment "$@" ;;
  comment-range) cmd_comment_range "$@" ;;
  summary)       cmd_summary "$@" ;;
  submit)        cmd_submit "$@" ;;
  discard)       cmd_discard "$@" ;;
  *)             usage ;;
esac
