---
name: review-code
description: Review code changes for quality and convention compliance. Supports both GitHub pull requests and local branches.
---

# Review Code Skill

Review code changes for quality and convention compliance. Supports both GitHub pull requests and local branches.

## Context Gathering

Extract the branch reference from the user's message. This can be one of:

1. **Current branch**: User says "review current branch" or similar
2. **Local branch name**: e.g., `feature/my-branch` or `paul/syncGitCouch`
3. **GitHub PR URL**: e.g., `https://github.com/EdgeApp/edge-react-gui/pull/123`
4. **GitHub PR number**: e.g., `#123` or `PR 123` (requires repository context)

### For GitHub Pull Requests

If a PR URL or number is provided:

1. Use the attached PR data from Cursor (available in `/pull-requests/pr-<number>/` folder) which contains:
   - `summary.json`: PR metadata including branch names, base branch, and changed files
   - `all.diff`: Complete diff of all changes
   - `diffs/`: Individual diff files per changed file
2. Identify the repository name and owner from the PR URL (e.g., `EdgeApp/edge-react-gui`)
3. Follow the **GitHub PR Checkout** section below

### For Local Branches

If a branch name is provided (not a PR):

1. Identify the repository from the current working directory or the user's prompt. If a repo name is given, locate it as a peer directory of `edge-conventions` (see **Repository Synchronization** for details).
2. Read the target repository's `AGENTS.md` and any `.cursor/rules/` files for repo-specific conventions.
3. Change to that repository directory
4. Verify the branch exists and check it out:
   ```bash
   git fetch origin
   git checkout <branch-name>
   # Or if branch doesn't exist locally:
   git checkout -b <branch-name> origin/<branch-name>
   ```
5. Determine the base branch for comparison (typically `master` or `main`):
   ```bash
   git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'
   ```
6. If the branch has uncommitted or unstaged changes (no commits beyond the base), use `git diff` for unstaged changes and `git diff --cached` for staged changes instead of `git diff <base>...HEAD`. No git checkout operations are needed in this case.
7. Skip the GitHub PR sections and proceed directly to **Review Process**

## Repository Synchronization (GitHub PRs)

1. Locate the target repository as a peer directory of `edge-conventions`. Determine the parent directory containing `edge-conventions` (e.g., if this skill is at `git/edge-conventions/.cursor/skills/review-code/SKILL.md`, the parent is `git/`). The target repo will be a sibling directory under that parent (e.g., `git/edge-react-gui` for the `edge-react-gui` repository).
2. Read the target repository's `AGENTS.md` and any `.cursor/rules/` files to understand repo-specific conventions. Pass these as context to the review subagents.
3. Change to that repository directory

### Detecting Fork vs Internal Branch

Get PR metadata including the head repository owner:

```bash
gh pr view <pr-number> --repo <owner>/<repo> \
  --json headRefName,headRepositoryOwner,baseRefName,headRepository
```

The JSON response includes:
- `headRepositoryOwner.login`: The owner of the source repository (fork owner or same org)
- `headRefName`: The branch name in the source repo
- `baseRefName`: The target branch (usually "master" or "main")

**Fork Detection Logic:**
- If `headRepositoryOwner.login` matches the base repo owner, it's an **internal branch**
- If they differ, it's a **fork** from an external user/organization

### GitHub PR Checkout

#### For Internal Branches (same organization)

```bash
git fetch origin
git checkout <head.ref>
# Or if branch doesn't exist locally:
git checkout -b <head.ref> origin/<head.ref>
```

#### For External/Fork Branches (different organization)

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

#### Verification

After checkout, verify you are on the correct branch:
```bash
git branch --show-current
git log --oneline -3  # Verify recent commits match PR
```

#### Fallback: Use Attached Diff Data (PRs Only)

If branch checkout fails (e.g., fork was deleted, network issues), use the attached PR diff data directly from `/pull-requests/pr-<number>/all.diff` for review. This contains the complete changes without requiring local checkout. Note that reviewing from diff alone may miss context from unchanged files that affect the review.

## Review Process

1. Get the complete diff:
   - **For local branches**: `git diff <base-branch>...HEAD` (e.g., `git diff master...HEAD`)
   - **For PRs with local checkout**: `git diff <base>...HEAD`
   - **For PRs without checkout**: Read the attached diff from `/pull-requests/pr-<number>/all.diff`

2. Identify which files were changed and categorize them (React components, cleaners, etc.)

3. Launch the `review-repo` subagent with the following context:
   - Repository name
   - Branch name
   - PR URL (if applicable, otherwise "local branch review")
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
   - `review-tests` for all files
   - `review-pr` for commit messages and PR structure
   - `review-servers` for server repositories (name ends in `-server` OR has `pm2.json` at repo root)

5. Compile findings from all subagents into a single review summary. Check existing PR reviews and comments to avoid duplicating feedback already provided by other reviewers—omit any findings that another reviewer has already raised.

## Output Format

Provide a structured review with:
- **Critical Issues**: Must be fixed before merge
- **Warnings**: Should be addressed
- **Suggestions**: Consider for improvement
- **Conventions Checklist**: Which conventions were checked and passed/failed

Save the review to a markdown document in the system temp directory (`/tmp` on macOS/Linux).

Name the document:
- **For PRs**: `MMDDhhmm_[repository-name]_[branch-name]_pr-[pr-number].md`
- **For local branches**: `MMDDhhmm_[repository-name]_[branch-name]_review.md`

**If running in the Cursor IDE GUI** (detected by the `CURSOR_TRACE_ID` environment variable being set), open the document in Cursor and pause for the user to review:

```bash
cursor --reuse-window <review-document-path>
```

**If running from a terminal-based agent** (Cursor CLI, opencode, crush, or similar), print the full path to the saved document.

**For GitHub PRs only:** Submit the review to GitHub using the process below.

**For local branches:** After the user reviews, offer to help fix any issues found or create a PR if desired.

## Submitting PR Review with Inline Comments (GitHub PRs Only)

Use the `gh` CLI to add comments inline to specific lines of code rather than one large summary comment. **Skip this section for local branch reviews.**

### Step 1: Build and Submit the Review

Get the head commit SHA:

```bash
gh pr view <pr-number> --repo <owner>/<repo> --json headRefOid --jq .headRefOid
```

Create a JSON file with the review body, event, and all inline comments, then submit it in a single API call:

```bash
cat > /tmp/review-payload.json << 'REVIEW_EOF'
{
  "commit_id": "<head-commit-sha>",
  "event": "REQUEST_CHANGES",
  "body": "## Review Summary\n\n[Brief summary of critical issues and positive observations]\n\nSee inline comments for specific issues.",
  "comments": [
    {
      "path": "src/path/to/file.ts",
      "line": 42,
      "side": "RIGHT",
      "body": "**Issue:** Description of the problem\n\n**Recommendation:**\n```typescript\n// suggested fix\n```"
    },
    {
      "path": "src/path/to/other.ts",
      "start_line": 10,
      "line": 15,
      "start_side": "RIGHT",
      "side": "RIGHT",
      "body": "**Warning:** Multi-line comment spanning a range"
    }
  ]
}
REVIEW_EOF

gh api repos/<owner>/<repo>/pulls/<pr-number>/reviews \
  --method POST \
  --input /tmp/review-payload.json
```

Use `"event": "REQUEST_CHANGES"` for critical issues, `"event": "COMMENT"` for suggestions only, or `"event": "APPROVE"` if no issues found.

### Comment Guidelines

**Add inline comments for:**
- Critical issues (with specific line references)
- Warnings (with specific line references)
- Suggestions that reference specific code locations

**Keep as summary body only:**
- General observations without specific line references
- Positive feedback
- Commit message issues
