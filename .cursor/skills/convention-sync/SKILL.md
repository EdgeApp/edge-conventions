---
name: convention-sync
description: Sync cursor files between ~/.cursor/ and the edge-conventions repo, commit, push, and update PR description. Use when the user wants to sync conventions.
compatibility: Requires git, gh.
metadata:
  author: j0ntz
---

<goal>Sync cursor files between `~/.cursor/` and the `edge-conventions` repo, commit, push, and update PR description from README.</goal>

<rules>
<rule id="use-companion-script">Use `scripts/convention-sync.sh` for diffing and syncing. Do NOT manually diff or copy files.</rule>
<rule id="dry-run-first">Always run without `--stage` first to show the summary. Only stage/commit after user confirms.</rule>
<rule id="no-script-bypass">If the script fails, report the error and STOP.</rule>
<rule id="readme-is-source">`.cursor/README.md` is the source of truth for documentation. The script mirrors it to the PR description automatically.</rule>
</rules>

<step id="1" name="Detect changes and PR status">
Determine the repo directory — default to the current working directory if it contains a `.cursor/` folder, otherwise use the `edge-conventions` checkout.

Run **in parallel**:
1. Sync script in dry-run mode:
   ```bash
   scripts/convention-sync.sh <repo-dir>
   ```
2. Check for open PR:
   ```bash
   cd <repo-dir> && gh pr view --json number,url --jq '{number: .number, url: .url}' 2>/dev/null || echo '{}'
   ```

Parse the JSON output. If `total` is 0, report "Everything is in sync" and stop.
</step>

<step id="2" name="Present summary">
Show the user a concise summary including PR update status:

```
Sync summary (user → repo):
  New: file1, file2
  Modified: file3, file4
  Deleted: file5
  Ignored: file6, file7 (via .syncignore)

PR #N: Will update description from README.md (or "No open PR")

Commit and push? [y/N]
```

If `ignored` array is empty, omit the Ignored line.

If the user provided a commit message in their prompt, skip the confirmation and proceed.
</step>

<step id="3" name="Stage, commit, push, update PR">
Run the script with `--commit`:

```bash
scripts/convention-sync.sh <repo-dir> --commit -m "<message>"
```

Then push:

```bash
cd <repo-dir> && git push origin HEAD
```

If an open PR exists, update the PR description from README:

```bash
cd <repo-dir> && gh pr edit --body-file .cursor/README.md
```
</step>

<edge-cases>
<case name="Reverse sync (repo → user)">If the user says "pull from repo" or "update my local", run with `--repo-to-user --stage` instead. No git operations needed.</case>
<case name="Selective sync">To permanently exclude files, add glob patterns to `~/.cursor/.syncignore` (one per line, `#` comments). The script skips matching entries and reports them in the `ignored` array. To exclude ad-hoc, remove files from staging with `git reset HEAD .cursor/<file>` before committing.</case>
<case name="No README">If `.cursor/README.md` doesn't exist, skip PR description update and warn the user.</case>
</edge-cases>
