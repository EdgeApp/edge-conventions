# [<](README.md) &nbsp; Commit rules

- [Subject Line](#subject-line)
  - [Use the imperative mood in the subject line](#use-the-imperative-mood-in-the-subject-line)
  - [Limit the subject line to 50 characters](#limit-the-subject-line-to-50-characters)
  - [Capitalize the subject line](#capitalize-the-subject-line)
  - [Do not end the subject line with a period](#do-not-end-the-subject-line-with-a-period)
- [Body](#body)
  - [Use the body to explain what and why vs. how](#use-the-body-to-explain-what-and-why-vs-how)
  - [Separate body from subject with a blank line](#separate-body-from-subject-with-a-blank-line)
  - [Wrap the body at 72 characters](#wrap-the-body-at-72-characters)
- [Standards](#standards)
  - [Clean commit principles](#clean-commit-principles)
  - [Rebasing](#rebasing)

&nbsp;

## Subject Line

---

### Use the imperative mood in the subject line

```bash
# incorrect
git commit -m "Fixed bug with Y"
git commit -m "Changing behavior of X"
git commit -m "More fixes for broken stuff"
git commit -m "Sweet new API methods"
```

```bash
# correct
git commit -m "Refactor subsystem X for readability"
git commit -m "Update getting started documentation"
git commit -m "Remove deprecated methods"
git commit -m "Release version 1.0.0"
```

### Limit the subject line to 50 characters

```bash
# incorrect (> 50 chars)
git commit -m "Add NEW_WALLET action to global action file and add NEW_WALLET action creator"
```

```bash
# correct
git commit -m "Add NEW_WALLET action and action creator"
```

### Capitalize the first letter of the first word in the subject line

```bash
# incorrect
git commit -m "accelerate to 88 miles per hour"
```

```bash
# correct
git commit -m "Accelerate to 88 miles per hour"
```

### Do not end the subject line with a period

```bash
# incorrect
git commit -m "Open the pod bay doors."
```

```bash
# correct
git commit -m "Open the pod bay doors"
```

[Back to the top](#--commit-rules)

## Body

---

### Use the body to explain what and why vs. how

```bash
# incorrect
git commit -m "Decrease time to send transaction

This pull request moves the http request to after signing and sending
transactions.
"
```

```bash
# correct
git commit -m "Decrease time to send transaction

The core makes an http request prior to sending each transaction. It
then waits for the return of this request before sending the
transaction. This request took several seconds and is not required to
to complete before sending the transaction.

Moving the request until after the transaction is sent decreases
the time the use spends waiting to send a transaction.
"
```

### Separate body from subject with a blank line

```bash
# incorrect

git commit -m "Derezz the master control program
MCP turned out to be evil and had become intent on world domination.
This commit throws Tron's disc into MCP (causing its deresolution)
and turns it back into a chess game."
```

```bash
# correct

git commit -m "Derezz the master control program

MCP turned out to be evil and had become intent on world domination.
This commit throws Tron's disc into MCP (causing its deresolution)
and turns it back into a chess game."
```

### Wrap the body at 72 characters

```bash
# incorrect (does not wrap at 72 chars)
git commit -m "Simplify serialize.h's exception handling

Remove the 'state' and 'exceptmask' from serialize.h's stream implementations, as well as related methods.

As exceptmask always included 'failbit', and setstate was always called with bits = failbit, all it did was immediately raise an exception. Get rid of those variables, and replace the setstate with direct exception throwing (which also removes some dead code)."
```

```bash
# correct
git commit -m "Simplify serialize.h's exception handling

Remove the 'state' and 'exceptmask' from serialize.h's stream
implementations, as well as related methods.

As exceptmask always included 'failbit', and setstate was always
called with bits = failbit, all it did was immediately raise an
exception. Get rid of those variables, and replace the setstate
with direct exception throwing (which also removes some dead
code)."
```

source: [How to Write a Git Commit Message](https://chris.beams.io/posts/git-commit/#seven-rules)

[Back to the top](#--commit-rules)

## Standards

Since open-source work is self-directed, there is no promise that anybody will want your work. Therefore, you need to work hard to convince the maintainers that your stuff is a good idea.

- Every commit should improve the code in some obvious way.
- Each commit should be stand-alone. They might want some and not others.
- No commit should break the program - all tests should pass, and all code should make sense at each point.

If you mess up, do not create another commit to fix it! Go back & repair the original commit, so that original commit will be desirable.

Put your commits in some sort of logical order, for example:

1. Delete dead code & perform simplications
2. Add new type definitions & helper components
3. Implement the feature
4. Remove old code that was replaced

Renaming files or variables should always happen in their own commits, separate from any code changes.

### Work-in-Progress Commits

When working on a feature that is not yet complete, you may use "WIP" as a prefix in the commit message:

```bash
# acceptable for incomplete work
git commit -m "WIP Theme server in Settings"
```

However, WIP commits should be cleaned up before creating a pull request. Use interactive rebase to either:
- Complete the work and update the commit message
- Split the WIP commit into logical, complete commits
- Remove the WIP prefix once the work is complete

WIP commits are useful for saving progress but should not be included in pull requests unless the PR is explicitly marked as a draft for early feedback.

### Clean Commit Principles

- Avoid doing something just to undo it a few commits later.
- The repo should build and be free of all mistakes after every commit.
- Each commit should be useful on its own if we had to cherry-pick it.

### Rebasing

Rebasing is your best friend when preparing your work for review. Your workflow can remain somewhat messy and disorganized to get the job done, however before you create a pull request for your work to be reviewed, you should interactively rebase (`git rebase -i`) to:

- Splitting: Separating unrelated changes in a commit
- Squashing: Join related commits together
- Reordering: Change the order of commits

See [Git - Rewritting History](https://git-scm.com/book/en/v2/Git-Tools-Rewriting-History) for a guide on how to accomplish these edits to your branch. Or, read the summary below.

#### Splitting commits

One commit makes 2 unrelated changes! How to split it?

If it’s simple:

1. Stop the rebase right before the commit that needs splitting.
2. Re-do and commit the first half of the changes.
3. Continue rebasing.

If it’s complex:

1. Use the “e” command to stop at the commit we need to split.
2. Create an “anitmatter” commit that un-does half the changes.
3. Revert the “antimatter” commit - this gives a clean commit that makes the changes.
4. Do another rebase to join the original commit & antimatter commits.


#### Joining commits

- Use the "fixup" or "f" command to join two commits keeping the first commit message
- Use the "squash" or "s" command to join two commits and edit the commit message
- Use “fixup!” “squash!” in your commit message and add `--autosquash` to your rebase command to tell git to automatically use these commands in your rebase.

#### Editing commits

- Use the "edit" or "e" command to edit commits. You can make small ammendments (`git commit --amend`), edit commit messages, etc.
- Make sure to run `yarn precommit && git rebase --continue` before commiting changes.
- You can even create whole new commits in this mode (omit `--amend`!

[Back to the top](#--commit-rules)
