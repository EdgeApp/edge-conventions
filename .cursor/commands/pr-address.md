<goal>Address PR feedback with fixup commits, using snapshot-first context and companion script for all deterministic operations.</goal>

<rules description="Non-negotiable constraints.">
<rule id="use-companion-script">Do NOT call `gh` directly. Use `~/.cursor/commands/pr-address.sh` for all GitHub API interactions (it uses `gh` internally).</rule>
<rule id="no-script-bypass">If a companion script fails, report the error and STOP. Do NOT fall back to raw `gh`, `curl`, or other workarounds.</rule>
<rule id="no-git-editor">All git commands that may open an editor (`rebase --continue`, `commit` without `-m`) MUST be prefixed with `GIT_EDITOR=true` to prevent blocking on `COMMIT_EDITMSG` in the IDE.</rule>
<rule id="no-gitkraken">NEVER use `git_log_or_diff:GitKraken`. Use local `git` commands directly.</rule>
<rule id="this-file-wins">If any other instruction conflicts with this file, **this file wins** for `pr-address`.</rule>
<rule id="commit-via-script">Commit fixups using `~/.cursor/commands/lint-commit.sh -m "fixup! {headline}" [files...]`. Do NOT manually run eslint — the commit script handles it.</rule>
<rule id="script-timeouts">GitHub API scripts can take up to 30s. Set `block_until_ms: 60000` when invoking `pr-address.sh`.</rule>
</rules>

<step id="1" name="Gather PR context">
Read the PR snapshot if available (fast, no network). Fall back to live API if missing.

<sub-step name="Snapshot available">
If the user referenced the PR via `@PR ...`, Cursor writes a snapshot folder. Read it:

```bash
~/.cursor/commands/pr-address.sh context --pr-dir "<snapshot-dir>"
```

Also read `comments.json` directly for full thread details including `threadsByFile`.
</sub-step>

<sub-step name="Snapshot missing or stale">
Fetch live from GitHub:

```bash
~/.cursor/commands/pr-address.sh fetch --owner <OWNER> --repo <REPO> --pr <NUMBER>
```

If the script exits code 2 with `PROMPT_GH_AUTH`, prompt: "`gh` CLI is not authenticated. Please run: `gh auth login`"
</sub-step>
</step>

<step id="2" name="Classify comments by recency">
Compare each comment's `createdAt` against the last commit timestamp (`git log -1 --format='%aI'`):

- **NEW**: `createdAt > lastCommitTime` — address automatically
- **OLD unresolved**: `createdAt <= lastCommitTime && !isResolved` — note for step 5

If there are NO new comments but OLD unresolved exist, prompt immediately:
> "No new comments since last commit. There are N older unresolved comments. Address them? [y/N]"
</step>

<step id="3" name="Process comments">
Group NEW comments by file. If the user provided specific files, scope to those only.

<sub-step name="Apply fixes">
1. Read each file with comments
2. Apply changes — comment hunks can be narrower than intent; apply consistently within the function/file
3. Commit using `lint-commit.sh`:
   ```bash
   ~/.cursor/commands/lint-commit.sh -m "fixup! {targetHeadline}" [files...]
   ```
</sub-step>

<sub-step name="Determine fixup target">
Ask: **"Which commit introduced the behavior/code this comment is about?"**

- List commits touching the file: `git log --oneline -- <file>`
- A specific line/function → fixup the commit that introduced it
- A missing feature/behavior → fixup the commit that should have included it
- A pattern/style issue → fixup the earliest commit where it appears
- Ambiguous → ask the user

Get the target commit headline:
```bash
git log -1 --format='%s' <commit_sha>
```
</sub-step>

<sub-step name="Reply to comments">
Reply to ALL processed comments — both addressed and rejected.

```bash
~/.cursor/commands/pr-address.sh reply \
  --owner <OWNER> --repo <REPO> --pr <NUMBER> \
  --comment-id <NUMERIC_ID> --body "<reply text>"
```

If the snapshot uses GraphQL node IDs, resolve to numeric first:
```bash
~/.cursor/commands/pr-address.sh resolve-id \
  --owner <OWNER> --repo <REPO> --pr <NUMBER> \
  --node-id "<PRRC_nodeId>"
```

**Reply guidelines:**
- **Addressed**: State what was fixed. Factual, 1 sentence.
- **Invalid/false-positive**: Brief evidence citing code paths or logic. 1-3 sentences.
- No pleasantries. Factual tone only.
</sub-step>
</step>

<step id="4" name="Autosquash (automated reviewers only)">
If ALL review comments came from automated reviewers (`chatgpt-codex-connector` or `cursor`), autosquash fixup commits:

```bash
~/.cursor/commands/pr-address.sh autosquash
```

If conflicts occur, resolve them, then: `GIT_EDITOR=true git rebase --continue`. If a commit becomes empty after squashing: `git rebase --skip`.

Then force push: `git push --force-with-lease`.
</step>

<step id="5" name="Prompt for older unresolved comments">
After processing NEW comments, if OLD unresolved comments remain, prompt:
> "Addressed N new comments. There are M older unresolved comments remaining:
> - [file:line] comment summary...
> Address these as well? [y/N]"

If confirmed, repeat step 3 for older comments.
</step>

<step id="6" name="Verification">
Run full verification to catch issues introduced by fixup commits:

```bash
~/.cursor/commands/verify-repo.sh . --base <upstream-ref>
```

Where `<upstream-ref>` is `origin/develop` for `edge-react-gui` or `origin/master` for other repos. Set `block_until_ms: 120000`.

If verification fails, fix the issue with another fixup commit, then re-run verification.
</step>

<step id="7" name="Post-processing">
Propose modifications to `~/.cursor/rules/typescript-standards.mdc` to prevent similar review comments in the future. Prompt for confirmation before applying.
</step>

<edge-cases>
<case name="No gh auth">Script exits code 2 with `PROMPT_GH_AUTH`. Prompt user to run `gh auth login` and STOP.</case>
<case name="Stale snapshot">If the snapshot `fetchedAt` predates the last push, prefer live data via `pr-address.sh fetch`.</case>
<case name="No new comments">Skip step 3. Go directly to step 5 to prompt about old unresolved comments.</case>
<case name="Human reviewer comments">Do NOT autosquash. Leave fixup commits for the reviewer to verify, then squash on merge.</case>
</edge-cases>
