---
name: convention-sync
description: Sync cursor files between ~/.cursor/ and the edge-conventions repo, commit, push, and update PR description. Use when the user wants to sync conventions.
compatibility: Requires git, gh.
metadata:
  author: j0ntz
---

<goal>Sync cursor files between `~/.cursor/` and the `edge-conventions` repo, commit, push, and update PR description from README. Also maintains cross-tool compatibility: symlinks `~/.claude/skills` → `~/.cursor/skills` and generates `~/.claude/CLAUDE.md` from always-apply rules.</goal>

<rules>
<rule id="local-is-canonical">`~/.cursor/` is the canonical source. Edits happen locally; the repo is the distribution copy. Default direction is `user-to-repo`. Use `--repo-to-user` only for onboarding or pulling changes authored by others. The script does not detect bidirectional conflicts — whichever direction you run overwrites the other side.</rule>
<rule id="use-companion-script">Use `~/.cursor/skills/convention-sync/scripts/convention-sync.sh` for diffing and syncing. Do NOT manually diff or copy files.</rule>
<rule id="dry-run-first">Always run without `--stage` first to show the summary. Only stage/commit after user confirms.</rule>
<rule id="no-script-bypass">If the script fails, report the error and STOP.</rule>
<rule id="readme-is-source">`.cursor/README.md` is the source of truth for documentation. The script mirrors it to the PR description automatically.</rule>
<rule id="claude-compat">Every run ensures `~/.claude/skills` symlinks to `~/.cursor/skills` and regenerates `~/.claude/CLAUDE.md` from `alwaysApply: true` rules. This enables OpenCode and Claude Code to discover skills and rules without separate config.</rule>
<rule id="target-repo-resolution">For user-to-repo sync, target the `edge-conventions` checkout. Do NOT assume the current repo is correct just because it contains a `.cursor/` folder. Let the companion script resolve and validate the repo path.</rule>
</rules>

<step id="1" name="Detect changes and PR status">
Use the companion script's default repo resolution first. It targets the `edge-conventions` checkout and fails if the resolved or provided repo is not actually `edge-conventions`.

Run the sync script in dry-run mode:

```bash
~/.cursor/skills/convention-sync/scripts/convention-sync.sh
```

Parse the JSON output and extract `repoDir`. Then check for an open PR:

```bash
cd <repo-dir> && gh pr view --json number,url --jq '{number: .number, url: .url}' 2>/dev/null || echo '{}'
```

Use the resolved repo path from the script for subsequent git and PR commands. If the script reports `total` as 0, report "Everything is in sync" and stop.
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
~/.cursor/skills/convention-sync/scripts/convention-sync.sh <repo-dir> --commit -m "<message>"
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
<case name="Current repo has a .cursor folder but is not edge-conventions">Do not sync into that repo. Fall back to `~/git/edge-conventions` or ask for the correct repo path.</case>
<case name="Dry-run resolved a repo path">Reuse the `repoDir` value from the script's JSON output for the PR query, commit run, push, and PR edit steps.</case>
<case name="Selective sync">To permanently exclude files, add glob patterns to `~/.cursor/.syncignore` (one per line, `#` comments). The script skips matching entries and reports them in the `ignored` array. To exclude ad-hoc, remove files from staging with `git reset HEAD .cursor/<file>` before committing.</case>
<case name="No README">If `.cursor/README.md` doesn't exist, skip PR description update and warn the user.</case>
</edge-cases>
