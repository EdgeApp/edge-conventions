# [<](README.md) &nbsp; Git "Future Commit" Workflow

- [Motivation](#motivation)
- [Creating a Future Commit](#creating-a-future-commit)
- [Multiple Future Commits](#multiple-future-commits)
- [Rewriting History](#rewriting-history)
  - [Step 1: Create new future commit](#step-1-create-new-future-commit)
  - [Step 2: Moving the dependent feature branch](#step-2-moving-the-dependent-feature-branch)
- [Removing Future Commits](#removing-future-commits)
- [Review Conventions](#review-conventions)
- [Git Alias](#git-alias)

&nbsp;

## Motivation

It's not uncommon for some feature to depend on the work of another feature on a separate branch. That feature's dependency may be in peer-review with an outstanding pull-request, or still a work-in-progress and not yet ready for review. Regardless, how can we build on top of that feature's dependency in a clean way that is relatively simple to manage and clear for the reviewer to follow?

This convention describes a workflow using "future commits" to organize and identify feature dependencies that have not yet been merged into the master branch. This is accomplished with a single commit for each anticipated merge of a feature, building a pseudo-master branch to be used until all feature dependencies (PRs) have been reviewed, approved, and merged.

[Back to the top](#--git-"future-commit"-workflow)

&nbsp;

## Creating a Future Commit

Say we have an existing feature branch, `feature-a`, that has yet to be merged into master, and we have another feature, `feature-b`, that we wish to have built on top of `feature-a`. We can do so by creating a pseudo-merge commit on master and build our `feature-b` from that commit.

```sh
git checkout master
git checkout -b feature-b
git merge --no-ff -m"future! feature-a" feature-a
git tag -f future/feature-a
```

This will first checkout master, create our second feature branch (`feature-b`), merge our dependency feature branch (`feature-a`) into our new branch, and then tag the merge commit with a conventional `future/feature-a` tag for a convenient reference to this point in history.

By convention, always use "future!" followed by the branch name as the commit message for the merge commit.

Now we're ready to make commits to `feature-b`. When we submit our PR, the reviewer can see our future commit and know that all the work prior to this future commit is to be reviewed separately within another PR.

[Back to the top](#--git-"future-commit"-workflow)

&nbsp;

## Multiple Future Commits

Let's say we're in the situation where we have a third feature which depends on `feature-b`. We can create a future commit for this using the same commands.

```sh
git checkout master
git checkout -b feature-c
git merge --no-ff -m"future! feature-b" feature-b
git tag -f future/feature-b
```

This time we created our new branch `feature-c` and merged `feature-b`. Finally we tagged this new merge commit with `future/feature-b`.

When submitting our PR for `feature-c`, the reviewer can see two future commits and know to review only the commits following the last future commit.

[Back to the top](#--git-"future-commit"-workflow)

&nbsp;

## Rewriting History

It's not uncommon for a feature to receive requested changes from a reviewer. When this happens on a feature that is a dependency for other features, we'll want to rebase our _dependent_ features onto the modified branch of the _dependency_ feature.

In the event that a dependency branch changes, we can leverage the `future/<branch-name>` tags we've created to rebase our branches. Let's say `feature-a` changes (e.g. a new commit is added), and we want to update `feature-b` to point to the new HEAD of `feature-a`.

### Step 1: Create new future commit

We'll first create a new future commit for the now modified `feature-a` branch. We can do this directly off of the master branch.

```sh
git checkout master --detach
git merge --no-ff -m"future! feature-a" feature-a
git tag -f future/feature-a
```

This is very similar to how we've been creating future commits previously. The only difference here is that we're creating the merge commit for our feature on top of master while in "detached HEAD" state because we don't have a new branch with which to create and work. By being in detached HEAD state, we don't make any changes to master when creating our merge commit. We can then tag the new commit with the `future/feature-a` tag as we usually do.

### Step 2: Moving the dependent feature branch

This leaves us with the tag pointing to the new future commit, and we can now rebase our other branch(es) onto the commit where the tag references. In our example, our other branch is `feature-b`, and we want it rebased onto the new future commit.

```sh
git rebase --onto future/feature-a 'feature-b^{/future! feature-a}' feature-b
```

This rebase looks complicated, but it's actually very simple if read from right to left (backwards): What it does is rebase commits from `feature-b` up to the commit with the commit message _"future! feature-a"_ in the `feature-b` branch onto the commit that the tag `future/feature-a` references.

```txt
before rebase:

           (a)---('feature-b^{/future! feature-a}')---(x)---(y)---(feature-b)
          /
--(master)
          \
           (a)---(b)---(future/feature-a)


after rebase:

--(master)
          \
           (a)---(b)---(future/feature-a)---(x)---(y)---(feature-b)
```

Essentially what we're wanting here is to make sure we move all the `feature-b` commits over to the new future commit, and we're able to by searching for the old future commit by it's commit message.

If we have more branches that depend on `feature-a`, we can repeat step 2 for each of those other branches.

If we have a branch that depends on `feature-b`, say `feature-c`, we can repeat steps 1 for `feature-b` and step 2 for `feature-c`.

[Back to the top](#--git-"future-commit"-workflow)

&nbsp;

## Removing Future Commits

When a feature's dependency is merged into master, we can use the same rebasing technique to remove the future commit for that dependency and bring our feature out of a work-in-progress state. The only difference is that we're going to rebase onto master rather than some future merge commit marked by some `future/<branch-name>` tag.

```sh
git rebase --onto master future/feature-a feature-b
```

This rebase our `feature-b` branch onto `master` up to the `future/feature-a` tag. This is a lot like our previous rebase command to move our `feature-b` branch onto an new future commit, but this time our new future commit is the actual merge commit.

If we have a `feature-c` that depended, on `feature-b` we can follow the rebasing technique previously discussed to move the `feature-c` branch to a new future commit for `feature-b`.

After all rebasing is completed, we can delete the `future/feature-a` tag for cleanup.

```sh
git tag -d future/feature-a
```

[Back to the top](#--git-"future-commit"-workflow)

&nbsp;

## Review Conventions

All PRs for features that that include one or more future commits should be "Draft" PRs on GitHub. This way a reviewer knows not to merge after approval until it is ready for merge.

The PR should be converted to "Open" once all the future commits have been removed because the feature dependencies have been merged to master. Only after this can the requester (or reviewer) merge the approved PR. _It is the responsibility of the requester to merge open and approved PRs._

[Back to the top](#--git-"future-commit"-workflow)

&nbsp;

## Git Alias

To make our lives a bit easier, here is a git alias which can be used to aid your workflow. Add this git alias to your `~/.gitconfig` file.

### git future [\<base-branch>] [\<future-branch>] [\<feature-branch>]

```sh
[alias]
  future = "!f(){\
    git haschanges && echo \"Cannot complete with changes in working tree\" && exit 1;\
    baseBranch=${1:-master};\
    futureBranch=${2:-$(git branch --show-current)};\
    featureBranch=$3;\
    if [ $baseBranch == $futureBranch ]; then echo \"base branch '$baseBranch' matches future-branch '$futureBranch'\"; exit 1; fi;\
    git checkout -b future/$futureBranch || git checkout future/$futureBranch;\
    git reset --hard $baseBranch;\
    git merge --no-ff -m\"future! $futureBranch\" $futureBranch && (\
      test $featureBranch && (\
        git checkout -b $featureBranch || \
          git rev-parse \"$featureBranch^{/future! $futureBranch}\" &> /dev/null && (\
            git rebase --rebase-merges --onto \"future/$futureBranch\" \"$featureBranch^{/future! $futureBranch}\" \"$featureBranch\"\
          ) || (\
            git rebase --rebase-merges \"future/$futureBranch\" \"$featureBranch\"\
          )\
      )\
    )\
  }; f"
```

This alias creates a new future-commit (merge commit) on top of the given `<base-branch>` for the given `<future-branch>`.
It will also maintain that the branch `future/<future-branch>` points to the future-commit; creating the branch if it doesn't exist, or hard-reseting the branch if it does exist.

The third argument, `<feature-branch>` is an optional feature branch which depends on the future-commit.
If provided, this branch will be rebased onto the future-commit.

#### Optionality

If no `<base-branch>` argument is given, it will default to `master`.

If no `<future-branch>` argument is given, it will default to the current checked out branch.

If no `<feature-branch>` argument is give, it will have no rebase effects.

#### Usage `git future main`

With `my-feature` checked out:

```txt
from:

--(main)
        \
         (a)---(b)---(my-feature)

to:

--(main)--------------------------(future/my-feature)
        \                        /
         (a)---(b)---(my-feature)
```

#### Usage `git future main my-feature`

Same as `git future main` when `my-feature` is checked out, but any branch may be checked.

#### Usage `git future main my-feature my-other-feature`

Rebases `my-other-feature` branch onto the a newly created future-commit all at once:

```txt
from:

--(main)
       |\
       | (a)---(b)---(my-feature)
        \
         (c)---(d)---(my-other-feature)

to:

--(main)--------------------------(future/my-feature)---(c)---(d)---(my-other-feature)
        \                        /
         (a)---(b)---(my-feature)
```

Also, useful to be able to update the `<feature-branch>` to a new future-branch/future-commit:


```txt
from:

--(main)--------------------------(future/my-feature)
      ||\                        /
      || (a)---(b)---(my-feature)
      | \
      |  *-----------------------------------------(<old future-commit>)---(c)---(d)---(my-other-feature)
       \                                          /
        (old a)---(old b)---(old my-other-feature)

to:

--(main)--------------------------(future/my-feature)---(c)---(d)---(my-other-feature)
        \                        /
         (a)---(b)---(my-feature)
```

[Back to the top](#--git-"future-commit"-workflow)
