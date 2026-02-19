<goal>Sync cursor files between `~/.cursor/` and the `edge-conventions` repo, commit, push, and optionally update the PR description.</goal>

<rules>
<rule id="use-companion-script">Use `~/.cursor/commands/convention-sync.sh` for diffing and syncing. Do NOT manually diff or copy files.</rule>
<rule id="dry-run-first">Always run without `--stage` first to show the summary. Only stage/commit after user confirms.</rule>
<rule id="no-script-bypass">If the script fails, report the error and STOP.</rule>
</rules>

<step id="1" name="Detect changes">
Determine the repo directory — default to the current working directory if it contains a `.cursor/` folder, otherwise use the `edge-conventions` checkout.

Run the script in dry-run mode (no flags):

```bash
~/.cursor/commands/convention-sync.sh <repo-dir>
```

Parse the JSON output. If `total` is 0, report "Everything is in sync" and stop.
</step>

<step id="2" name="Present summary">
Show the user a concise summary:

```
Sync summary (user → repo):
  New: file1, file2
  Modified: file3, file4
  Deleted: file5

Commit and push? [y/N]
```

If the user provided a commit message in their prompt, skip the confirmation and proceed.
</step>

<step id="3" name="Stage, commit, push">
Run the script with `--commit`:

```bash
~/.cursor/commands/convention-sync.sh <repo-dir> --commit -m "<message>"
```

Then push:

```bash
cd <repo-dir> && git push origin HEAD
```
</step>

<step id="4" name="Update PR description (if needed)">
Only if new commands, scripts, or rules were added (check `new` array):

1. Detect the open PR for the current branch:
   ```bash
   gh pr view --json number,url --jq '.number' 2>/dev/null
   ```
   If no PR exists, skip this step.

2. Ask:
   > "New files added: file1, file2. Update PR #N description? [y/N]"

3. If confirmed, read the current PR body via `gh pr view --json body --jq '.body'`, add entries for new files in the appropriate tables, and update via `gh pr edit --body-file /tmp/pr-body.md`.
</step>

<edge-cases>
<case name="Reverse sync (repo → user)">If the user says "pull from repo" or "update my local", run with `--repo-to-user --stage` instead. No git operations needed.</case>
<case name="Selective sync">If the user says to exclude specific files, note them but still run the full diff. The script syncs everything — manually skip files by not confirming, or remove them from staging with `git reset HEAD .cursor/<file>` before committing.</case>
</edge-cases>
