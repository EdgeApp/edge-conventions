# scrapebugs

Scrape bug-fix pull requests from repositories, analyze the root causes, and propose preventive rules for review subagents.

## Parameters

Parse the user's message for these optional parameters:

| Parameter | Format | Default |
|-----------|--------|---------|
| **repository** | Repository name (e.g., "edge-react-gui") | edge-react-gui |
| **time window** | "past N days/weeks/months" or date range | Past 30 days |

### Examples

- `scrapebugs` → edge-react-gui, past 30 days
- `scrapebugs edge-core-js` → Single repo, past 30 days
- `scrapebugs past 2 weeks` → edge-react-gui, past 2 weeks
- `scrapebugs edge-exchange-plugins past 3 months` → Single repo, past 3 months
- `scrapebugs all repos` → All EdgeApp repos, past 30 days

## Repositories

When "all repos" is specified, process all EdgeApp repositories:

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
  { id: "fetch-prs", content: "Fetch bug-fix PRs", status: "in_progress" },
  { id: "analyze-bugs", content: "Analyze bug causes", status: "pending" },
  { id: "propose-rules", content: "Propose preventive rules", status: "pending" },
  { id: "generate-report", content: "Generate summary report", status: "pending" }
]
```

### Handle GitHub Rate Limits

GitHub API allows 5000 requests/hour for authenticated users. If you hit rate limits:

```
Attempt 1: Wait 1 minute, retry
Attempt 2: Wait 2 minutes, retry
Attempt 3: Wait 4 minutes, retry
Attempt 4: Wait 8 minutes, retry
Attempt 5+: Wait 16 minutes, retry (cap at 16 minutes)
```

---

## Workflow

### Step 1: Calculate Time Range

Convert the time window to a date for filtering:

```
Default: 30 days ago from today
"past N days": subtract N days
"past N weeks": subtract N * 7 days
"past N months": subtract N months
```

Use this date to filter PRs by `merged_at` timestamp.

### Step 2: Fetch Bug-Fix PRs

Use GitHub MCP to search for bug-fix PRs:

```
CallMcpTool: user-github / search_pull_requests
Arguments: {
  "query": "repo:EdgeApp/<repo-name> is:pr is:merged merged:>=<date> (label:bug OR \"fix\" in:title OR \"bug\" in:title)"
}
```

**Alternative approach** - List all merged PRs and filter:

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

Filter results to include PRs where:
- `merged_at` is not null AND within the time window
- AND one of:
  - Has "bug" label
  - Title contains: "fix", "bug", "crash", "error", "issue", "broken", "incorrect", "wrong"
  - Title starts with common fix patterns: "Fix", "Bugfix", "Hotfix"

**Exclude** PRs that are clearly not bug fixes:
- "fix lint", "fix types", "fix tests" (tooling fixes)
- "fix typo" (documentation)
- New features that happen to use "fix" in context

### Step 3: Fetch PR Details

For each identified bug-fix PR, get full details:

```
CallMcpTool: user-github / get_pull_request
Arguments: {
  "owner": "EdgeApp",
  "repo": "<repo-name>",
  "pullNumber": <number>
}
```

Also fetch the diff to understand what changed:

```
CallMcpTool: user-github / get_pull_request_diff
Arguments: {
  "owner": "EdgeApp",
  "repo": "<repo-name>",
  "pullNumber": <number>
}
```

### Step 4: Analyze Each Bug

For each bug-fix PR, extract:

1. **Bug Cause** - What was wrong? Analyze the diff to understand:
   - Was it a logic error?
   - Missing null/undefined check?
   - Race condition?
   - Incorrect API usage?
   - Missing error handling?
   - State management issue?
   - Type mismatch?

2. **Fix Type** - How was it fixed? Categorize:
   - Added null/undefined check
   - Fixed conditional logic
   - Added error handling
   - Fixed async/await issue
   - Corrected type
   - Fixed state update
   - Added missing dependency
   - Removed incorrect code

3. **Root Cause Category** - Map to review subagent:

| Root Cause Pattern | Target Review Agent |
|-------------------|---------------------|
| Missing error handling, uncaught exceptions | review-errors |
| React hook issues, component lifecycle | review-react |
| State not updating, stale closures, Redux issues | review-state |
| Race conditions, timing, async issues | review-async |
| Invalid data handling, type mismatches | review-cleaners |
| Misleading comments, missing docs | review-comments |
| Git/merge issues | review-pr |
| Hardcoded strings, localization | review-strings |
| Logic errors, naming confusion | review-code-quality |

### Step 5: Propose Preventive Rules

For each analyzed bug, create a proposed rule:

```markdown
### PR #<number>: <title>

**Bug Cause:** <1-2 sentence description of what went wrong>

**Fix Type:** <category>

**Root Cause Category:** <review-agent-name>

**Proposed Rule:**

> **<Rule Title>**
>
> <Description of what to check for during code review>
>
> ```typescript
> // Incorrect - what the buggy code looked like
> <simplified example>
>
> // Correct - what the fix looks like
> <simplified example>
> ```

**Link:** https://github.com/EdgeApp/<repo>/pull/<number>
```

### Step 6: Generate Summary Report

Create a temporary document with all findings.

First, ensure the output directory exists:
```bash
mkdir -p .cursor/tmp
```

Then write the report to:
`.cursor/tmp/bug-analysis-<repo>-<date>.md`

Example: `.cursor/tmp/bug-analysis-edge-react-gui-2026-01-28.md`

---

## Output Format

Generate a comprehensive report:

```markdown
# Bug Analysis Report

**Repository:** EdgeApp/<repo-name>
**Time Window:** <start date> to <end date>
**Generated:** <current date>

## Summary Statistics

- Total PRs scanned: X
- Bug-fix PRs identified: X
- Bugs by category:
  - Error handling: X
  - React/hooks: X
  - State management: X
  - Async issues: X
  - Data validation: X
  - Other: X

---

## Bug Analysis

### PR #123: Fix crash when wallet is undefined

**Bug Cause:** The code assumed `wallet` would always be defined, but it can be undefined during the brief period after account creation before wallets are loaded.

**Fix Type:** Added null check

**Root Cause Category:** review-errors

**Proposed Rule:**

> **Check for undefined wallet references**
>
> When accessing wallet properties, verify the wallet exists first. Wallets may be undefined during loading states or after deletion.
>
> ```typescript
> // Incorrect - assumes wallet exists
> const balance = wallet.balances[currencyCode]
>
> // Correct - guard against undefined
> const balance = wallet?.balances[currencyCode] ?? '0'
> ```

**Link:** https://github.com/EdgeApp/edge-react-gui/pull/123

---

### PR #456: Fix race condition in sync

...

---

## Proposed Rules Summary

Rules ready to add to review subagents:

### review-errors.md
1. "Check for undefined wallet references" (from PR #123)
2. "Handle async errors in useEffect cleanup" (from PR #789)

### review-react.md
1. "Verify hook dependencies include all referenced values" (from PR #456)

### review-state.md
1. "Check for stale closure in callbacks" (from PR #234)

---

## Next Steps

To add these rules to review subagents, run:
`/scraperev` with manual review, or manually add selected rules to:
- `/Users/paul/git/edge-conventions/.cursor/agents/review-errors.md`
- `/Users/paul/git/edge-conventions/.cursor/agents/review-react.md`
- etc.
```

---

## Duplicate Detection

Before proposing a rule, check if similar guidance already exists:

1. Read the target review agent file
2. Search for similar patterns or keywords
3. If duplicate found:
   - Note "Similar to existing rule: <rule name>"
   - Only propose if the new bug reveals a different angle

---

## Tips for Accurate Bug Identification

### Good Indicators of Bug Fixes

- PR title contains: "fix", "bug", "crash", "error", "broken", "issue #"
- PR labels include: "bug", "bugfix", "hotfix", "regression"
- PR description mentions: "fixes", "resolves", "closes #"
- Diff shows defensive checks being added
- Diff shows error handling being added
- Diff is small and focused (not a feature)

### False Positives to Exclude

- "Fix lint errors" - tooling, not bugs
- "Fix typo in comment" - documentation
- "Fix test" - test maintenance
- "Fix build" - CI/tooling
- Refactoring PRs that happen to improve code
- Feature PRs with "fix" in unrelated context

### When Uncertain

If a PR might be a bug fix but you're not sure:
- Include it in the report
- Mark as "Possible bug fix - needs review"
- Let the user decide whether to create a rule

---

## Resume from Interruption

If interrupted, the user can specify:
- `scrapebugs --resume` → Agent asks what was last processed
- `scrapebugs --resume PR#123` → Resume after PR #123

Report current progress state if interrupted so user knows where to resume.
