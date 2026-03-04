---
name: pr-create
description: Create a pull request from the current branch, with optional Asana attach/assign updates.
compatibility: Requires git, gh, node, jq. ASANA_TOKEN for Asana updates. ASANA_GITHUB_SECRET for Asana PR attachment (obtain via https://github.integrations.asana.plus/auth?domainId=ghactions).
metadata:
  author: j0ntz
---

<goal>Create a PR from the current branch, optionally attach it to Asana and assign reviewer.</goal>

<rules description="Non-negotiable constraints.">
<rule id="use-companion-script">Do NOT call `gh` directly for PR creation. Use `~/.cursor/skills/pr-create/scripts/pr-create.sh`.</rule>
<rule id="no-script-bypass">If a companion script fails, report the error and STOP. Do NOT fall back to raw `gh`, `curl`, or workarounds.</rule>
<rule id="gh-auth-required">If script exits code 2 with `PROMPT_GH_AUTH`, prompt user to run `gh auth login` and STOP.</rule>
<rule id="no-dirty-pr">Do NOT create a PR when there are uncommitted changes.</rule>
<rule id="no-base-push">Do NOT push to `master`/`develop` directly.</rule>
<rule id="verification-required">Run verification before creating the PR.</rule>
<rule id="flag-contract">`--asana-attach`/`--asana-assign` only run when a task GID is available from chat context or explicit `--asana-task <gid>`. If no task GID is available, fail fast and skip Asana updates.</rule>
<rule id="script-timeouts">Asana updates can take up to 90s. Use `block_until_ms: 120000` for `asana-task-update.sh` calls.</rule>
</rules>

<step id="1" name="Push branch">
Push current branch if needed:

```bash
git push -u origin HEAD
```

If tracking is already configured and branch is up to date, skip.
</step>

<step id="2" name="Verification">
Run:

```bash
~/.cursor/skills/verify-repo.sh . --base <upstream-ref>
```

Use `origin/develop` for `edge-react-gui` and `origin/master` for other repos.
</step>

<step id="3" name="Build PR description">
Gather context in parallel:

```bash
DEFAULT_BRANCH=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|origin/||' || git remote show origin 2>/dev/null | sed -n '/HEAD branch/s/.*: //p' || echo master)
git log origin/$DEFAULT_BRANCH..HEAD --format=%B---
```

Build title/body using repo template and branch commits. If Asana context is available from chat or fetched via `--asana-task`, include a `#### Context` subsection in Description.
</step>

<step id="4" name="Create PR">
Write body to `/tmp/pr-body.md`, then run:

```bash
~/.cursor/skills/pr-create/scripts/pr-create.sh \
  --title "<title>" \
  --body-file /tmp/pr-body.md \
  [--asana-task <task_gid>]
```

Capture PR URL and number from JSON output.
</step>

<step id="5" name="Optional Asana updates">
If neither `--asana-attach` nor `--asana-assign` was requested, skip.

If either flag is requested, resolve `task_gid` from:

1. explicit `--asana-task <gid>` argument
2. chat context (previous task-review/im context)

If no task GID is available, fail fast and report:

> Asana flags were requested but no task GID was found in flags or chat context.

Then call:

```bash
~/.cursor/skills/asana-task-update/scripts/asana-task-update.sh \
  --task <task_gid> \
  [--attach-pr --pr-url <pr_url> --pr-title "<title>" --pr-number <number>] \
  [--assign --set-status "Review Needed" --auto-est-review-hrs]
```

- `--asana-attach` maps to `--attach-pr ...`
- `--asana-assign` maps to `--assign --set-status "Review Needed" --auto-est-review-hrs`
- If both are set, combine in one command.
</step>

<step id="6" name="Report result">
Display PR URL as a clickable markdown link:

`[owner/repo#123](https://github.com/owner/repo/pull/123)`
</step>

<edge-cases>
<case name="Branch already has an open PR">Report the existing PR URL and stop.</case>
<case name="No gh auth">Prompt user to run `gh auth login` and stop.</case>
<case name="Rebase needed">Ask user before rebasing and force-pushing.</case>
</edge-cases>
