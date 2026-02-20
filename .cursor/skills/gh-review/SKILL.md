---
name: gh-review
description: Orchestrate a GitHub PR review session — start a pending review, add inline comments interactively, and submit only when the user explicitly confirms.
---

# GitHub PR Review Skill

Orchestrate an interactive code review session on a GitHub pull request. The review stays in a pending (draft) state while the user adds comments over one or more turns. The review is only submitted after explicit user confirmation.

## Prerequisites

- `gh` CLI installed and authenticated (`gh auth status`)
- Repository cloned locally with the PR accessible
- `jq` installed (used by the helper script)

## Context Gathering

Extract from the user's message:

1. **PR reference**: URL, number, or "current PR"
2. **Comment instruction**: What to comment on, which file/line, or a review document to draw from

## Session Lifecycle

A review session has three phases: **Start**, **Comment**, and **Submit**.

### Phase 1: Start

Start or resume a pending review:

```bash
gh-review.sh start <pr-number>
```

Returns JSON with session details:

```json
{
  "status": "created",
  "node_id": "PRR_kwDO...",
  "database_id": "123456",
  "owner": "EdgeApp",
  "repo": "edge-conventions",
  "number": "28",
  "url": "https://github.com/..."
}
```

`status` is either `"created"` (new review) or `"resumed"` (existing pending review found).

Save `node_id`, `database_id`, `owner`, `repo`, and `number` for subsequent calls.

Tell the user a pending review has been started (or resumed).

### Phase 2: Comment

Each time the user asks to add a comment, use the appropriate subcommand.

**Single-line comment:**

```bash
gh-review.sh comment <node_id> <path> <line> "<body>"
```

**Multi-line comment (spanning a range):**

```bash
gh-review.sh comment-range <node_id> <path> <start_line> <end_line> "<body>"
```

Line numbers must reference lines present in the PR diff (RIGHT side). To verify a line is commentable:

```bash
gh pr diff <pr-number>
```

After each comment is added, confirm to the user what was posted and where.

### Phase 3: Submit (only after explicit confirmation)

**Do NOT submit the review until the user explicitly asks.**

When the user indicates they are done, get a summary:

```bash
gh-review.sh summary <owner> <repo> <pr-number>
```

Returns JSON with all pending comments (bodies truncated to 60 chars). Present to the user:

```
Review for PR #<number> — <total_comments> inline comments:

1. <path>:<line> — <truncated body>
2. <path>:<line> — <truncated body>
...

Submit as: APPROVE / COMMENT / REQUEST_CHANGES ?
```

**Wait for the user to confirm** the event type and give the go-ahead.

Once confirmed:

```bash
gh-review.sh submit <owner> <repo> <pr-number> <database_id> <EVENT> "<optional body>"
```

Valid events:
- `APPROVE` — No issues found
- `COMMENT` — Suggestions only, no blocking issues
- `REQUEST_CHANGES` — Critical issues that must be fixed

### Discarding a Review

If the user wants to abandon the pending review:

```bash
gh-review.sh discard <owner> <repo> <pr-number> <database_id>
```

Confirm deletion to the user.

## Direct `gh` CLI Fallback

If the helper script is unavailable or doesn't cover a specific use case, you can call the GitHub API directly via `gh`. Key constraints to be aware of:

| Operation | Method |
|-----------|--------|
| Create pending review | REST: `gh api repos/{owner}/{repo}/pulls/{number}/reviews -f commit_id="<sha>"` — omit `event` |
| Add comment to existing pending review | **Must use GraphQL** — REST returns 422 if a pending review exists. Use `addPullRequestReviewThread` mutation with the review's `node_id`. |
| Submit review | REST: `gh api repos/{owner}/{repo}/pulls/{number}/reviews/{id}/events -f event="<EVENT>"` |
| Delete pending review | REST: `gh api repos/{owner}/{repo}/pulls/{number}/reviews/{id} -X DELETE` |
| Query pending review | GraphQL query on `pullRequest.reviews(states: PENDING)` |

The critical constraint: the REST `POST /pulls/{number}/comments` endpoint always tries to create a new pending review, conflicting with any existing one. Always use GraphQL `addPullRequestReviewThread` to add comments incrementally to an existing pending review.
