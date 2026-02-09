---
name: fix-pr
description: Address reviewer comments on a GitHub pull request by creating a fix plan, iterating with the user, implementing fixes, and pushing changes.
---

# Fix PR Skill

Address reviewer comments on a GitHub pull request. Creates a plan document, iterates with the user, implements fixes with fixup commits, then pushes changes to GitHub.

## Context Gathering

Extract the PR reference from the user's prompt:

1. **GitHub PR URL**: e.g., `https://github.com/EdgeApp/edge-react-gui/pull/123`
2. **GitHub PR number**: e.g., `#123` or `PR 123` (requires repository context)

Identify the repository name and owner from the PR URL or context.

## Collecting Reviewer Comments

Use the GitHub MCP server to fetch reviewer comments from the PR:

1. Fetch PR details and all review comments using the GitHub MCP tools
2. Look for:
   - Line-level review comments
   - General PR comments with actionable feedback
   - Requested changes from reviewers

## Filtering Comments

Skip comments where:
- The developer responded and declined to implement the change
- The reviewer marked the comment as resolved
- The comment is purely informational with no action required

## Creating the Fix Plan

1. For each remaining comment, determine which commit introduced the code being reviewed
2. Review the comment thread to understand the required changes
3. Write a structured plan document to the system temp directory (`/tmp` on macOS/Linux)

### Plan Document Format

Name the document: `MMDDhhmm_[repository-name]_[branch-name]_pr-[pr-number]_fixplan.md`

Structure the plan as:

```markdown
# Fix Plan for PR #[number]

**Repository**: [owner/repo]
**Branch**: [branch-name]
**Generated**: [timestamp]

## Summary

[Brief overview of changes needed]

## Fixes

### Fix 1: [Brief description]

- **File(s)**: [file paths]
- **Commit**: [commit hash that introduced the code]
- **Reviewer Comment**: [summary of the feedback]
- **Planned Change**: [what will be changed]

### Fix 2: [Brief description]

...
```

4. Open the plan document in the current Cursor workspace for the user to review:
   ```bash
   cursor --reuse-window <plan-document-path>
   ```

## User Iteration

**PAUSE HERE** and wait for the user to:
- Review the plan
- Request modifications
- Add or remove items
- Approve the plan to proceed

Do not proceed until the user explicitly confirms the plan.

## Implementing Fixes

Once the user approves the plan, process each fix item:

For each fix in the plan:

1. Save the current branch head hash as `BRANCHHEAD`
2. Re-identify the commit to fix by examining `git log --oneline` and matching the commit message or content from the plan (original commit hashes become stale after history rewrites)
3. Save the newly identified hash as `FIXUPHASH`
4. Check out the commit needing changes: `git checkout ${FIXUPHASH}`
5. Make the necessary code changes (edit files, stage them)
6. Test changes with `yarn precommit` and fix any failures
7. Stage and create the fixup commit: `git add -A && git commit --fixup HEAD --no-verify`
8. Cherry-pick remaining commits: `git cherry-pick "${FIXUPHASH}..${BRANCHHEAD}"`
9. Resolve any conflicts
10. Update the branch to the new history: `git checkout -B <branch-name>`

Repeat for each fix item. **Important**: After each iteration, the branch history is rewritten, so commit hashes from the original plan are no longer valid. Always re-identify commits using `git log` at the start of each iteration.

## Pushing Changes to GitHub

After all fixes are implemented:

1. Verify all fixup commits are in place: `git log --oneline`
2. Force push the branch to update the PR:
   ```bash
   git push --force-with-lease origin <branch-name>
   ```
3. Optionally, reply to resolved review comments on GitHub using the MCP server

## Important Warnings

- **DO NOT AUTO SQUASH** - Leave fixup commits visible so the reviewer can see what changed
- **Use --force-with-lease** - Never use `--force` to avoid overwriting others' changes
- Running `yarn precommit` manually then committing with `--no-verify` is intentional to avoid duplicate hook execution
