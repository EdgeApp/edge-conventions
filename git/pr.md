# [<](README.md) &nbsp; Pull Request Rules

- [Use "future commits" and rebasing for feature dependencies](#use--future-commits--and-rebasing-for-feature-dependencies)
- [Use "fixup commits" for changes from PR feedback](#use--fixup-commits--for-changes-from-pr-feedback)
  - [Example](#example)
  - [Modifying commit messages](#modifying-commit-messages)

&nbsp;

## Use "future commits" and rebasing for feature dependencies

- When `branch-b` builds on `branch-a`, but `branch-a` has not yet been merged into master, create a fake merge commit for `branch-a` and build `branch-b` at that merge commit. Use "future! branch-a" as the commit message.

- Use [GitHub's draft pull-request](https://github.blog/2019-02-14-introducing-draft-pull-requests/) feature when creating the PR for `branch-b`. This will signal to the reviewer(s) that the PR is a work-in-progress. The draft status can be removed once `branch-b` has been rebased onto master and there are no longer future-commits in the branch.

- For an in-depth guide into this workflow see: [Workflow Conventions](future-commit.md)

&nbsp;

## Use "fixup commits" for changes from PR feedback

- When a reviewer requests a change during review of a PR, the pull-requester should use "fixup commits" to resolve each requested change. The fixup commit will include the prefix "fixup!" followed by the commit message of the commit it is fixing.

  ```bash
  git commit --fixup <commit-hash>
  ```

  These fixup commits will make it simpler to review each change in isolation and make it simpler to determine if a requested change is adequately resolved.

- Once all feedback has been resolved, the fixup commits should be squashed into the relevant commit using `git rebase -i --autosquash <commit-hash>`. Git will automatically move all fixup commits into their correct place with the correct rebase action for you.

- You can enable autosquash by default using `git config --global rebase.autosquash true`; this way you can do `git rebase -i <commit-hash>` without the need for the `--autosquash` argument.

- You can create fixup commits with `git commit --fixup <commit-hash>` or you can use the commit message: `git commit --fixup ':/Commit message'`. Using `:/` followed by the commit message will tell git to find the most recent commit matching the message text that you provided. Git will partially match your commit message text if you don't enter it fully, however be mindful that you don't unintentionally match the wrong commit.

[Back to the top](#--pull-request-rules)

&nbsp;

### Example

---

Let's say your feature is a new component, and some configurations need changing to go along with your feature.

```bash
git commit -m"Add an awesome component to a screen"
# ...
git commit -m"Updated some configurations for awesome component"
```

During review, the reviewer requests a change in your component's code. You then create the fixup commit.

```bash
git commit --fixup ':/Add an awesome component to a screen'
```

But, this change also effects the configuration. So, make another fixup commit so it can be squashed separately.

```bash
git commit --fixup ':/Updated some configurations for awesome component'
```

Now, the reviewer can clearly see the changes made, and the outstanding issues can be reviewed.

Once all reviewing is complete and the PR is approved, the requester must squash the commits using rebase:

```bash
git rebase -i --autosquash HEAD~4
```

_In editor:_

```txt
pick abc111 fixup! Add an awesome component to a screen
fixup abc333 fixup! Add an awesome component to a screen
pick abc222 Updated some configurations for awesome component
fixup abc444 fixup! Updated some configurations for awesome component
```

After rebasing, the requester will force push the changes to update the PR. If there are no more commits left to rebase and no code changes left to be reviewed, the PR should be merged by requester. The reviewer has the option to merge as well.

[Back to the top](#--pull-request-rules)

&nbsp;

### Modifying commit messages

---

Alternatively, you can use the `--squash` argument instead of `--fixup`. This will give you the opportunity to add something to the commit message for the "fixup commit" (or "squash commit"). Keep in mind, that you must leave the "squash!" line of text in your commit message for git to know where to place your commit when rebasing your commit using autosquash. E.g.

```txt
squash! My cool feature

My cool feature with extra coolness
```

When rebasing, git will mark your squash commit with the `squash` rebase action, and it will give you the opportunity to edit the final commit message (it'll include the original commit message and the squash commit message in your terminal editor):

```txt
# This is a combination of 2 commits.
# This is the 1st commit message:

My cool feature

# This is the commit message #2:

squash! My cool feature

My cool feature with extra coolness
```

You can delete the all the lines but the last line to replace the commit message for your final commit.

[Back to the top](#--pull-request-rules)
