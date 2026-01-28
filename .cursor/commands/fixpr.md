# fixpr

## Overview

Address reviewer comments on a pull request by creating fixup commits. Process one comment at a time, one commit at a time.

## Steps

1. Identify the target from the user's prompt. The user may specify:
   - A GitHub pull request URL or number (use the GitHub MCP server)
   - Locally edited files (use git status to find changes)
   - A specific branch name (use git log to find commits)
2. Collect all reviewer comments from:
   - The GitHub pull request (if a PR was specified)
   - A document specified in the prompt
   Skip comments where the developer responded and declined to implement the change.
3. For each remaining comment, determine which commit introduced the code being reviewed.
4. Review the comment thread to understand the required changes.
5. Write a summary of planned changes to a file in `/tmp`, open it in Cursor, and ask the user to confirm before proceeding.

## Creating Fixup Commits

For each comment requiring changes:

1. Save the current branch head hash as `BRANCHHEAD`
2. Save the hash of the commit to fix as `FIXUPHASH`
3. Check out the commit needing changes: `git checkout ${FIXUPHASH}`
4. Make the necessary code changes
5. Test changes with `yarn precommit` and fix any failures
6. Create the fixup commit: `git commit --fixup HEAD --no-verify`
7. Cherry-pick remaining commits: `git cherry-pick "${FIXUPHASH}..${BRANCHHEAD}"`
8. Resolve any conflicts
9. Update the branch to the new history: `git checkout -B <branch-name>`

Repeat for each comment that needs addressing.

## Important

- **DO NOT PUSH THE BRANCH**
- **DO NOT AUTO SQUASH**
- Running `yarn precommit` manually then committing with `--no-verify` is intentional to avoid duplicate hook execution
