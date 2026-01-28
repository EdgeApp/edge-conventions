# scraperev

Scrape PR review comments from repositories and add accepted patterns as rules to review subagent documents.

## Parameters

Parse the user's message for these optional parameters:

| Parameter | Format | Default |
|-----------|--------|---------|
| **repository** | Repository name (e.g., "edge-react-gui") | All repositories |
| **time window** | "past N days/weeks/months" or date range | Past 1 month |

### Examples

- `scrape-reviews` → All repos, past month
- `scrape-reviews edge-react-gui` → Single repo, past month
- `scrape-reviews past 2 weeks` → All repos, past 2 weeks
- `scrape-reviews edge-core-js past 3 months` → Single repo, past 3 months

## Repositories

When no repository is specified, process all EdgeApp repositories:

- edge-react-gui
- edge-currency-accountbased
- edge-core-js
- edge-currency-plugins
- edge-login-ui-rn
- edge-exchange-plugins
- edge-currency-monero
- edge-login-server

## Long-Running Execution

This command can take significant time when processing multiple repositories. Follow these practices to ensure completion:

### Use Todo List for Progress Tracking

Create a todo list at the start to track progress:

```
TodoWrite: [
  { id: "repo-1", content: "edge-react-gui", status: "pending" },
  { id: "repo-2", content: "edge-currency-accountbased", status: "pending" },
  ...
]
```

Mark each repository as `in_progress` when starting, `completed` when done.

### Process One Repository at a Time

Complete all steps for one repository before moving to the next:
1. Fetch PRs for repo
2. Get comments for each PR
3. Extract candidate rules
4. Report progress
5. Move to next repo

This ensures partial progress is preserved if interrupted.

### Checkpoint After Each Repository

After completing each repository, output a progress update:

```
✓ Completed edge-react-gui (15 PRs, 42 comments, 3 candidates)
→ Starting edge-currency-accountbased...
```

### Stage Rules Before Writing

Collect all candidate rules in memory first. Write to review files only after ALL repositories are processed. This prevents partial updates if interrupted.

### Handle GitHub Rate Limits

GitHub API allows 5000 requests/hour for authenticated users. If you hit rate limits (403 responses, "rate limit exceeded" messages), use exponential backoff:

```
Attempt 1: Wait 1 minute, retry
Attempt 2: Wait 2 minutes, retry
Attempt 3: Wait 4 minutes, retry
Attempt 4: Wait 8 minutes, retry
Attempt 5+: Wait 16 minutes, retry (cap at 16 minutes)
```

During each wait:
1. Report current progress and wait duration
2. Use `sleep` command to wait the required time
3. Retry the failed API call
4. Reset backoff counter after a successful call

Example output during rate limiting:
```
⚠ Rate limited. Progress: edge-react-gui complete, edge-core-js PR #45
  Waiting 1 minute before retry...
  [after wait] Retrying...
  ⚠ Still rate limited. Waiting 2 minutes before retry...
```

Continue retrying at 16-minute intervals until successful. Do not give up or ask the user to retry later.

### Batch PR Comment Fetching

When a repository has many PRs, process in batches of 10-20 PRs. Report progress after each batch:

```
Processing edge-react-gui PRs 1-20 of 45...
Processing edge-react-gui PRs 21-40 of 45...
Processing edge-react-gui PRs 41-45 of 45...
```

### Recommended Initial Runs

For first-time use, start with constrained parameters:
- Single repository: `scraperev edge-react-gui`
- Short time window: `scraperev past 1 week`
- Both: `scraperev edge-react-gui past 2 weeks`

Expand scope once you've verified the workflow works correctly.

---

## Workflow

### Step 1: Calculate Time Range

Convert the time window to a date for filtering:

```
Default: 1 month ago from today
"past N days": subtract N days
"past N weeks": subtract N * 7 days
"past N months": subtract N months
```

Use this date to filter PRs by `merged_at` timestamp.

### Step 2: Fetch Merged PRs

For each repository (or the single specified one), use GitHub MCP:

```
CallMcpTool: user-github / list_pull_requests
Arguments: {
  "owner": "EdgeApp",
  "repo": "<repo-name>",
  "state": "closed",
  "sort": "updated",
  "direction": "desc",
  "perPage": 100
}
```

Filter results to include only PRs where:
- `merged_at` is not null (was actually merged)
- `merged_at` is within the time window

Paginate if necessary to get all PRs within the time window.

### Step 3: Get Review Comments

For each merged PR within the time window:

```
CallMcpTool: user-github / pull_request_read
Arguments: {
  "method": "get_review_comments",
  "owner": "EdgeApp",
  "repo": "<repo-name>",
  "pullNumber": <number>
}
```

### Step 4: Filter Accepted Comments

A comment is **accepted** (not rejected by PR author) if ANY of:
- Thread is resolved (`isResolved` = true)
- Author acknowledged: "fixed", "done", "good point", "will do", "thanks"
- Code at that location was modified in a later commit

A comment is **rejected** if:
- Author pushed back ("I disagree", "I prefer", "Let's keep it") AND code wasn't changed
- Reviewer withdrew the comment

When uncertain, **include** the comment.

### Step 5: Categorize by Topic

Route each accepted comment to the appropriate review subagent:

| Pattern Keywords | Target File |
|-----------------|-------------|
| try, catch, throw, Error, showError, @ts-expect-error | review-errors.md |
| useEffect, useState, useCallback, React.FC, JSX, hooks | review-react.md |
| Redux, useSelector, disklet, dataStore, module state | review-state.md |
| setInterval, makePeriodicTask, background, polling | review-async.md |
| asObject, asString, cleaners, API validation | review-cleaners.md |
| comments, documentation, JSDoc, TODO | review-comments.md |
| commit message, git, rebase, PR structure | review-pr.md |
| lstrings, en_US.json, localization, hardcoded string | review-strings.md |
| naming, dead code, unused, organization | review-code-quality.md |

### Step 6: Check for Duplicates

Before adding a rule, read the target file at:
`.cursor/agents/<file>`

Check for:
1. **Exact duplicate** - Same concept already documented → skip
2. **Similar rule** - Related rule exists → update to include new info

### Step 7: Add or Update Rules

**New rule format:**

```markdown
---

## Rule Title

Brief description of the pattern or anti-pattern.

\`\`\`typescript
// Incorrect - explanation
<bad example>

// Correct - explanation
<good example>
\`\`\`
```

**When updating existing rules:**
- Add examples if the new case differs
- Expand description to cover new scenarios
- Preserve existing guidance

### Comments to Skip

Do not create rules for:
- Typo corrections
- Style preferences without reasoning
- Project-specific details (not generalizable)
- Questions/clarifications
- Simple mistakes ("oops, you're right")
- Generic feedback ("looks good", "nice")

## Resume from Interruption

If the command is interrupted, it can be resumed. The agent should:

1. Check for existing progress by asking the user what was last completed
2. Skip already-processed repositories
3. Continue from the next repository in the list

When resuming, the user can specify:
- `scraperev --resume` → Agent asks for last completed repo
- `scraperev --resume edge-core-js` → Resume after edge-core-js

### Progress State

Maintain this state throughout execution:

```typescript
{
  timeWindow: { start: Date, end: Date },
  repositories: [
    { name: "edge-react-gui", status: "completed", prsProcessed: 15, candidateRules: [...] },
    { name: "edge-currency-accountbased", status: "in_progress", prsProcessed: 8, candidateRules: [...] },
    { name: "edge-core-js", status: "pending" },
    ...
  ],
  totalCandidateRules: [...]
}
```

If interrupted, report this state so the user knows where to resume.

---

## Output

Track and report:

```markdown
## Scrape Reviews Summary

**Time window:** [start date] to [today]
**Repositories:** [list or "all"]

### Statistics
- PRs scanned: X
- Review comments processed: X
- Accepted comments: X

### Rules Added
- review-errors.md: "Rule Name" (PR #123)
- review-react.md: "Rule Name" (PR #456)

### Rules Updated
- review-state.md: "Existing Rule Name" - added example from PR #789

### Skipped (Duplicates)
- "Similar to existing rule X in review-errors.md"
```

## Categorization Details

### review-errors.md
- Error handling, try/catch patterns
- Stack trace preservation
- Error variable naming
- @ts-expect-error usage
- null/undefined semantics
- Async error handling

### review-react.md
- Component exports (React.FC pattern)
- Hook usage (useHandler vs useCallback)
- Selector granularity
- JSX conditionals
- Event typing

### review-state.md
- Redux vs local state
- Module-level cache bugs
- DataStore API usage
- Settings storage
- Data format migrations

### review-async.md
- setInterval → makePeriodicTask
- TanStack Query usage
- Background service location
- Polling patterns

### review-cleaners.md
- Clean all external data
- Let cleaners handle JSON parsing
- Derive types from cleaners
- Remove unused cleaner fields

### review-comments.md
- Add non-obvious constraints
- Remove stale comments
- Explain why, not what

### review-pr.md
- Commit message format
- Clean commit principles
- Fixup commits
- Future commits for dependencies

### review-strings.md
- No hardcoded user-facing strings
- Reuse existing strings
- Context-based key names

### review-code-quality.md
- Meaningful variable names
- Delete unused code
- Inline parameters
- Use existing helpers
