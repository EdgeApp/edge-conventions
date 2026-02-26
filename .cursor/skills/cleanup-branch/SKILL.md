---
name: cleanup-branch
description: Create logical local commits for repository changes after implementation/review loops. Use when code changes are complete and need clean commit history before opening PRs.
---

# Cleanup Branch

Create logical local commits from working tree changes. This skill commits locally and does not push.

## Inputs

- `REPO_PATHS`: One or more repository paths to clean up.
- Optional `PLAN_DOC`: Planning document path for context.
- Commit/PR convention reference: `~/git/edge-conventions/.cursor/agents/review-pr.md`

## Workflow

For each `REPO_PATH`:

1. Gather context:

```bash
git -C "<REPO_PATH>" status --short
git -C "<REPO_PATH>" diff --name-only
```

2. Reason about commit boundaries from intent, not folder layout. Use plan/review context and group changes into logical units such as:
   - feature behavior
   - bug fix
   - refactor
   - tests
   - docs/config

   Apply the commit structure and message guidance from `review-pr`:
   - subject uses imperative mood
   - subject is <= 50 chars, capitalized, no trailing period
   - body explains what/why (not how), separated by a blank line
   - commits are clean, stand-alone, and logically ordered

3. For each logical unit:
   - stage only files for that unit
   - create one commit with a concise message
   - repeat until all repo changes are committed

```bash
git -C "<REPO_PATH>" add <file1> <file2> ...
git -C "<REPO_PATH>" commit -m "<message>"
```

4. Verify:

```bash
git -C "<REPO_PATH>" status --short
git -C "<REPO_PATH>" log --oneline -n 5
```

## Notes

- If one file mixes unrelated concerns, split the code changes first, then commit each concern separately.
- Keep commits reviewable and self-contained.
- This skill intentionally creates commits but does not push or open PRs.
