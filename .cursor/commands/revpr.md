# revpr

Review a GitHub pull request for code quality and convention compliance.

## Context Gathering

1. Extract the PR URL or number from the user's message
2. Use the attached PR data from Cursor (available in `/pull-requests/pr-<number>/` folder) which contains:
   - `summary.json`: PR metadata including branch names, base branch, and changed files
   - `all.diff`: Complete diff of all changes
   - `diffs/`: Individual diff files per changed file
3. Identify the repository name and owner from the PR URL (e.g., `EdgeApp/edge-react-gui`)

## Repository Synchronization

1. Find the matching repository directory in the workspace by name (do NOT use absolute paths - search the workspace for a directory matching the repository name)
2. Change to that repository directory

### Detecting Fork vs Internal Branch

Use the GitHub MCP server to get PR metadata including the head repository owner:

```
CallMcpTool: user-github / pull_request_read
Arguments: {
  "method": "get",
  "owner": "<base-repo-owner>",
  "repo": "<repo-name>",
  "pullNumber": <pr-number>
}
```

The response includes:
- `head.repo.owner.login`: The owner of the source repository (fork owner or same org)
- `head.ref`: The branch name in the source repo
- `base.ref`: The target branch (usually "master" or "main")
- `base.repo.owner.login`: The owner of the target repository

**Fork Detection Logic:**
- If `head.repo.owner.login` equals `base.repo.owner.login`, it's an **internal branch**
- If they differ, it's a **fork** from an external user/organization

### For Internal Branches (same organization)

```bash
git fetch origin
git checkout <head.ref>
# Or if branch doesn't exist locally:
git checkout -b <head.ref> origin/<head.ref>
```

### For External/Fork Branches (different organization)

First, check if the remote already exists:
```bash
git remote -v | grep <head.repo.owner.login>
```

If the remote doesn't exist, add it:
```bash
git remote add <head.repo.owner.login> https://github.com/<head.repo.owner.login>/<repo-name>.git
```

Then fetch and checkout:
```bash
git fetch <head.repo.owner.login>
git checkout -b pr-<pr-number> <head.repo.owner.login>/<head.ref>
```

**Complete Example** for PR #426 from org "onitsoft" to EdgeApp/edge-exchange-plugins:
```bash
# Check if remote exists
git remote -v | grep onitsoft

# Add remote if needed
git remote add onitsoft https://github.com/onitsoft/edge-exchange-plugins.git

# Fetch and checkout
git fetch onitsoft
git checkout -b pr-426 onitsoft/feature/nexchange-centralized-swap
```

### Verification

After checkout, verify you are on the correct branch:
```bash
git branch --show-current
git log --oneline -3  # Verify recent commits match PR
```

### Fallback: Use Attached Diff Data

If branch checkout fails (e.g., fork was deleted, network issues), use the attached PR diff data directly from `/pull-requests/pr-<number>/all.diff` for review. This contains the complete changes without requiring local checkout. Note that reviewing from diff alone may miss context from unchanged files that affect the review.

## Review Process

1. Get the complete diff using one of:
   - `git diff <base>...HEAD` if the branch is checked out locally
   - Read the attached diff from `/pull-requests/pr-<number>/all.diff`
2. Identify which files were changed and categorize them (React components, cleaners, etc.)

3. Launch the `review-repo` subagent with the following context:
   - Repository name
   - Branch name
   - PR URL
   - Base branch
   - Summary of changed files

4. Launch category-specific review subagents in parallel based on changed files:
   - `review-react` for `.tsx` component files
   - `review-cleaners` for all files
   - `review-errors` for all files
   - `review-state` for all files
   - `review-async` for all files
   - `review-code-quality` for all files
   - `review-comments` for all files
   - `review-strings` for all files
   - `review-pr` for commit messages and PR structure

5. Compile findings from all subagents into a single review summary. Check existing PR reviews and comments to avoid duplicating feedback already provided by other reviewers—omit any findings that another reviewer has already raised.

## Output Format

Provide a structured review with:
- **Critical Issues**: Must be fixed before merge
- **Warnings**: Should be addressed
- **Suggestions**: Consider for improvement
- **Conventions Checklist**: Which conventions were checked and passed/failed

Save the review to a markdown document in the system temp directory (`/tmp` on macOS/Linux), then open it in Cursor for the user to review. Name the document: `[repository-name]_[branch-name]_[pr-number].md`

Pause for the user to review.

Once the user has iterated and agreed on the changes, submit the review to GitHub.

## Submitting PR Review with Inline Comments

Use the GitHub MCP server to add comments inline to specific lines of code rather than one large summary comment.

### Step 1: Create a Pending Review

```
CallMcpTool: user-github / pull_request_review_write
Arguments: {
  "method": "create",
  "owner": "<repo-owner>",
  "repo": "<repo-name>",
  "pullNumber": <pr-number>,
  "commitID": "<head-commit-sha>"
}
```

**Note:** Do NOT include the `event` parameter yet - this creates a pending review that allows adding inline comments.

### Step 2: Add Inline Comments

For each issue that references a specific file and line, add an inline comment:

```
CallMcpTool: user-github / add_comment_to_pending_review
Arguments: {
  "owner": "<repo-owner>",
  "repo": "<repo-name>",
  "pullNumber": <pr-number>,
  "path": "src/path/to/file.ts",
  "line": <line-number>,
  "side": "RIGHT",
  "subjectType": "LINE",
  "body": "**Issue:** Description of the problem\n\n**Recommendation:**\n```typescript\n// suggested fix\n```"
}
```

For multi-line comments spanning a range:
```
Arguments: {
  ...
  "startLine": <first-line>,
  "line": <last-line>,
  "startSide": "RIGHT",
  "side": "RIGHT",
  "subjectType": "LINE"
}
```

**Add inline comments for:**
- Critical issues (with specific line references)
- Warnings (with specific line references)
- Suggestions that reference specific code locations

**Keep as summary only:**
- General observations without specific line references
- Positive feedback
- Commit message issues

### Step 3: Submit the Review

After adding all inline comments, submit the pending review:

```
CallMcpTool: user-github / pull_request_review_write
Arguments: {
  "method": "submit_pending",
  "owner": "<repo-owner>",
  "repo": "<repo-name>",
  "pullNumber": <pr-number>,
  "event": "REQUEST_CHANGES",
  "body": "## Review Summary\n\n[Brief summary of critical issues and positive observations]\n\nSee inline comments for specific issues."
}
```

Use `event: "REQUEST_CHANGES"` for critical issues, `event: "COMMENT"` for suggestions only, or `event: "APPROVE"` if no issues found.
