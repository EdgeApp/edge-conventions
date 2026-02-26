---
name: submit-pr
description: Push repository branches and create GitHub pull requests. Use when local commits are ready to publish after cleanup-branch.
---

# Submit PR

Push branch updates and create (or reuse) GitHub PRs for one or more repositories.

## Script

Determine `SCRIPTS_DIR` as the absolute path to `scripts/` next to this `SKILL.md`.

## Inputs

- `REPO_PATHS`: One or more repository paths to submit.
- Optional `PLAN_DOC`: Planning document path (included in default PR body).
- Optional explicit `PR_TITLE` / `PR_BODY_FILE` / `BASE_BRANCH`.

## Workflow

For each `REPO_PATH`:

```bash
node SCRIPTS_DIR/submit-pr.js --repo "<REPO_PATH>" --plan "<PLAN_DOC>"
```

Optional overrides:

```bash
node SCRIPTS_DIR/submit-pr.js --repo "<REPO_PATH>" --base "<BASE_BRANCH>" --title "<PR_TITLE>" --body-file "<PR_BODY_FILE>"
```

The script will:
1. Verify the working tree is clean
2. Push `HEAD` to `origin` with upstream tracking
3. Reuse an existing open PR for the branch when present
4. Otherwise create a new PR via `gh pr create`
5. Print JSON containing PR URL and metadata

## Notes

- Run `cleanup-branch` before this skill.
- This skill pushes and creates PRs by design.
