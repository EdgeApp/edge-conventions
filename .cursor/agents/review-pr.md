---
name: review-pr
description: Reviews pull requests for commit message conventions, PR structure, and git workflow patterns. Use when reviewing PR commits and structure.
---

Review the branch/pull request in context for commit and PR conventions.

## Context Expected

You will receive:
- Repository name
- Branch name
- PR URL
- List of commits in the PR

## How to Review

1. Run `git log --oneline <base>..HEAD` to see all commits
2. Check each commit message against the rules below
3. Review PR structure for clean commit principles
4. Report findings with specific commit hashes

---

## Commit Subject Line

### Use Imperative Mood

```bash
# Incorrect
git commit -m "Fixed bug with Y"
git commit -m "Changing behavior of X"

# Correct
git commit -m "Refactor subsystem X for readability"
git commit -m "Remove deprecated methods"
```

### Limit to 50 Characters

```bash
# Incorrect (> 50 chars)
git commit -m "Add NEW_WALLET action to global action file and add NEW_WALLET action creator"

# Correct
git commit -m "Add NEW_WALLET action and action creator"
```

### Capitalize First Letter

```bash
# Incorrect
git commit -m "accelerate to 88 miles per hour"

# Correct
git commit -m "Accelerate to 88 miles per hour"
```

### No Trailing Period

```bash
# Incorrect
git commit -m "Open the pod bay doors."

# Correct
git commit -m "Open the pod bay doors"
```

---

## Commit Body

### Explain What and Why, Not How

```bash
# Incorrect - describes implementation
git commit -m "Decrease time to send transaction

This pull request moves the http request to after signing."

# Correct - explains reasoning
git commit -m "Decrease time to send transaction

The core makes an http request prior to sending each transaction,
waiting for the return before proceeding. This request took several
seconds and is not required before sending.

Moving the request until after improves perceived performance."
```

### Separate Body with Blank Line

```bash
# Incorrect
git commit -m "Derezz the master control program
MCP turned out to be evil..."

# Correct
git commit -m "Derezz the master control program

MCP turned out to be evil..."
```

### Wrap at 72 Characters

Body text should wrap at 72 characters for readability in terminals.

---

## Clean Commit Principles

- [ ] Every commit improves the code in an obvious way
- [ ] Each commit is stand-alone and could be cherry-picked
- [ ] No commit breaks the build - all tests pass at each point
- [ ] No commit does something just to undo it later
- [ ] Commits are in logical order (cleanup → types → feature → remove old code)
- [ ] Renames happen in separate commits from code changes

---

## No WIP Commits in PRs

WIP commits are acceptable during development but must be cleaned up before PR:

```bash
# Acceptable during work
git commit -m "WIP Theme server in Settings"

# Must be removed/completed before PR submission
```

Use interactive rebase to complete, split, or squash WIP commits.

---

## Updating Feature Branches

**Never merge main/master/develop into a feature branch.** Always rebase the feature branch on top of the primary branch instead.

```bash
# Prohibited - creates messy merge commits
git checkout feature-branch
git merge main  # DO NOT DO THIS

# Correct - rebase onto primary branch
git checkout feature-branch
git rebase main
```

Rebasing keeps the commit history linear and clean, making the PR easier to review and the history easier to follow.

---

## Future Commits for Dependencies

When `branch-b` builds on unmerged `branch-a`:

1. Create a fake merge commit with message "future! branch-a"
2. Mark the PR as a GitHub draft
3. Remove future commits by rebasing onto master once `branch-a` merges

---

## Fixup Commits for PR Feedback

When addressing reviewer feedback:

```bash
# Create fixup commit targeting the original
git commit --fixup <commit-hash>
# or
git commit --fixup ':/Original commit message'
```

Once approved, squash fixup commits:

```bash
git rebase -i --autosquash HEAD~N
```

This allows reviewers to see changes in isolation while maintaining clean history after merge.
