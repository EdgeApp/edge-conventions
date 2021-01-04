# Git "Future-Commit" Workflow

## Motivation

It's not uncommon for some feature to depend on the work of another feature on a separate branch. That feature's dependency may be in peer-review with an outstanding pull-request, or still a work-in-progress and not yet ready for review. Regardless, how can we build ontop of that feature's dependency in a clean way that is relatively simple to manage and clear for the reviewer to follow?

This convention describes a workflow using "future commits" to organize and identify feature dependencies that have not yet been merged upstream (master branch). This is accomplished with a single commit for each anticipated merge of a feature, building a psuedo-master branch to be used until all feature dependencies (PRs) have been reviewed, approved, and merged.

## Creating a "future merge commit"

Say we have an existing feature branch, `feature-a`, that has yet to be merged into master, and we have another feature, `feature-b`, that we wish to have built on top of `feature-a`. We can do so by creating a psuedo-merge commit on master and build our `feature-b` from that commit.

```sh
git checkout master
git checkout -b feature-b
git merge --no-ff -m"future! feature-a" feature-a
git tag -f future/feature-a
```

This will first checkout master, create our second feature branch (`feature-b`), merge our dependency feature branch (`feature-a`) into our new branch, and then tag the merge commit with a conventional `future/feature-a` tag for a convenient reference to this point in history.

By convention, always use "future!" followed by the branch name as the commit message for the merge commit.

Now we're ready to make commits to `feature-b`! When we submit our PR, the reviewer can see our merge commit and know that all the work prior to this merge commit is to be reviewed separately with another PR.

## Multiple future merges

Let's say we're in the situation where we have a third feature which depends on `feature-b`. We can create a future commit for this using the same technique.

```sh
git checkout master
git checkout -b feature-c
git merge --no-ff -m"future! feature-b" feature-b
git tag -f future/feature-b
```

This time we created our new branch `feature-c` and merged `feature-b`. Finally we tagged this new merge commit with `future/feature-b`. 

Notice, we're always starting with master, creating a new branch, and merging the feature dependencies. We could turn this pattern into a git alias for convenience:

```
[alias]
  timetravel = "!f(){\
      git checkout master;\
      git checkout -b $1;\
      git merge --no-ff --no-verify -m"future! $2" $2;\
      git tag -f future/$2;\
    }; f"
```

Add this to your `~/.gitconfig` file. We can use it like so:

```sh
git timetravel <new-branch> <dependency-branch>
# Example:
git timetravel feature-a feature-b
```

## Rewritting History

In the event that one of our dependency branches changes, we can use the `future/` tags we've been creating to rebase our branches. Let's say `feature-a` changes (e.g. new commit), and we want to update `feature-b` to point to the new HEAD of `feature-a`.

We'll first need to create a second tag at `future/feature-a` called `past/feature-a`. This is so we can modify the `future/` tag without losing a reference to the commit it used to point to.

```sh
git tag -f past/feature-a future/feature-a
```

Now we shall checkout master and re-create our history.

```sh
git checkout master
git merge --no-ff -m"future! feature-a" feature-a
git tag -t future/feature-a
git reset --hard master@{1}
```

Notice we created the future commit on master, updated our `future/feature-a` tag to point to that new commit, then we reset master back. Now we have a new future commit and a reference to it with the `future/feature-a` tag.

Next we can rebase `feature-b` onto the new future commit.

```sh
git rebase --onto future/feature-a past/feature-a feature-b
```

This will rebase `feature-b` onto the commit at `future/feature-a` up to the comment where `past/feature-a` references (the old future commit). You can think about it like we're taking the commits from `past/feature-a` up to `feature-b` and re-applying them onto `future/feature-a`.

Finally, we'll need to cleanup the `past/feature-a` tag:

```sh
git tag -d past/feature-a
```

### Continued Rewrites

What about our other branches (`feature-c`)? We con apply the same rebase technique to these branches as well.

```
git checkout master
git merge --no-ff -m"future! feature-b" feature-b
git tag -t future/feature-b
git reset --hard master@{1}
git rebase --onto future/feature-b past/feature-b feature-c
git tag -d past/feature-b
```

These are the same rebasing steps, only we're rebasing `feature-c` onto a new future commit at the `future/feature-b` tag.

## Removing Future Commits

When a feature's dependency is merged into master, we can use the same rebasing technique to remove the `future/` tag for that dependency and bring our feature out of a work-in-progress or draft state. The only difference is that we're going to rebase onto master rather than some future merge commit marked by a `future/` tag.

```
git rebase --onto master future/feature-a feature-b
```

This rebases our `feature-b` branch onto `master` up to the `future/feature-a` checkpoint.

If we have a `feature-c` that depended, on `feature-b` we can follow the rebasing technique previously discussed to fix the `feature-c` branch.

After all rebasing is completed, we can delete the `future/feature-a` tag for cleanup. It's no longer needed; the future for `feature-a` is now!