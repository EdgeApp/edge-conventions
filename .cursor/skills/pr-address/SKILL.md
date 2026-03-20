---
name: pr-address
description: Address PR feedback with fixup commits, resolving each comment after replying. Use when the user wants to address review comments on a pull request.
compatibility: Requires git, gh.
metadata:
  author: j0ntz
---

<goal>Address PR feedback with fixup commits, resolving each comment after replying with how it was addressed.</goal>

<rules description="Non-negotiable constraints.">
<rule id="use-companion-script">Do NOT call `gh` directly. Use `~/.cursor/skills/pr-address/scripts/pr-address.sh` for all GitHub API interactions (it uses `gh` internally).</rule>
<rule id="no-script-bypass">If a companion script fails, report the error and STOP. Do NOT fall back to raw `gh`, `curl`, or other workarounds.</rule>
<rule id="no-git-editor">All git commands that may open an editor (`rebase --continue`, `commit` without `-m`) MUST be prefixed with `GIT_EDITOR=true` to prevent blocking on `COMMIT_EDITMSG` in the IDE.</rule>
<rule id="no-gitkraken">NEVER use `git_log_or_diff:GitKraken`. Use local `git` commands directly.</rule>
<rule id="this-file-wins">If any other instruction conflicts with this file, **this file wins** for `pr-address`.</rule>
<rule id="commit-via-script">Commit fixups using `~/.cursor/skills/lint-commit.sh --no-reorder -m "fixup! {headline}" [files...]`. `--no-reorder` is required — the default reorder runs `rebase --autosquash` which squashes fixups immediately, conflicting with step 4's conditional autosquash. Do NOT manually run eslint — the commit script handles it.</rule>
<rule id="script-timeouts">GitHub API scripts can take up to 30s. Set `block_until_ms: 60000` when invoking `pr-address.sh`.</rule>
<rule id="reply-before-resolve">ALWAYS reply explaining how a comment was addressed BEFORE resolving or marking it. No silent resolutions.</rule>
<rule id="resolution-source-of-truth">Only explicitly resolved threads (`isResolved: true`) or `<!-- addressed:... -->` markers count as resolved. Recency (commits after a comment) does NOT mean resolved.</rule>
</rules>

<step id="1" name="Fetch all unresolved feedback and PR body">
Always fetch live from GitHub. Run both in parallel:

```bash
# Fetch unresolved feedback
~/.cursor/skills/pr-address/scripts/pr-address.sh fetch --owner <OWNER> --repo <REPO> --pr <NUMBER>

# Populate /tmp/pr-body.md from the live PR body (source of truth)
~/.cursor/skills/pr-address/scripts/pr-address.sh fetch-pr-body --owner <OWNER> --repo <REPO> --pr <NUMBER>
```

If either script exits code 2 with `PROMPT_GH_AUTH`, prompt: "`gh` CLI is not authenticated. Please run: `gh auth login`"

The `fetch` output contains:
- **prAuthor**: The PR author's GitHub username
- **currentUser**: Your GitHub username (the authenticated `gh` user)
- **hasHumanReviewers**: `true` if any external human reviewer (not `currentUser`, not bots) has commented — used for autosquash decision
- **humanReviewers**: List of external human reviewer usernames
- **threads**: All unresolved inline review threads (includes comments from `currentUser` for context)
- **reviewBodies**: Latest review body per non-author reviewer (excludes `prAuthor` and bots)
- **topLevel**: Top-level comments (excludes `prAuthor` and bots)

To inspect a specific inline thread, including an already-resolved one, use:

```bash
~/.cursor/skills/pr-address/scripts/pr-address.sh fetch-thread \
  --owner <OWNER> --repo <REPO> --pr <NUMBER> \
  --thread-id "<PRRT_threadNodeId>"
```

The `fetch-pr-body` call writes the current PR body to `/tmp/pr-body.md`. This file is available for editing throughout the session. If you need to update the PR body (e.g. to revise the description after addressing feedback), edit `/tmp/pr-body.md` via the Write tool and push it back:

```bash
gh pr edit <NUMBER> --body-file /tmp/pr-body.md
```
</step>

<step id="2" name="Process all unresolved feedback">
Address every item returned by `fetch`. Group inline threads by file. If the user provided specific files, scope to those only.

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

<sub-step name="Apply fixes">
1. Read each file with comments
2. Apply changes — comment hunks can be narrower than intent; apply consistently within the function/file
3. Commit using `lint-commit.sh`:
   ```bash
   ~/.cursor/skills/lint-commit.sh --no-reorder -m "fixup! {targetHeadline}" [files...]
   ```
</sub-step>

<sub-step name="Push fixup commits">
After all fixup commits are created, push to the remote so the reviewer can see the changes referenced in replies:

```bash
git push
```
</sub-step>
</step>

<step id="3" name="Reply and resolve each comment">
After fixing, reply to every processed comment — addressed or rejected — then resolve it.

<sub-step name="Inline threads (reply → resolve)">
If a later fix may affect an already-addressed inline thread, inspect the thread first:

```bash
~/.cursor/skills/pr-address/scripts/pr-address.sh fetch-thread \
  --owner <OWNER> --repo <REPO> --pr <NUMBER> \
  --thread-id "<PRRT_threadNodeId>"
```

Use the returned history to decide whether the existing reply still fully reflects the latest fix. If it does not, add one new factual follow-up reply. Multiple replies in the same thread are acceptable when they capture materially new fixes.

1. Reply to the first comment in the thread:
   ```bash
   ~/.cursor/skills/pr-address/scripts/pr-address.sh reply \
     --owner <OWNER> --repo <REPO> --pr <NUMBER> \
     --comment-id <NUMERIC_ID> --body "<what was fixed>"
   ```

   If the comment ID is a GraphQL node ID, resolve to numeric first:
   ```bash
   ~/.cursor/skills/pr-address/scripts/pr-address.sh resolve-id \
     --owner <OWNER> --repo <REPO> --pr <NUMBER> \
     --node-id "<PRRC_nodeId>"
   ```

2. Then mark the thread as resolved:
   ```bash
   ~/.cursor/skills/pr-address/scripts/pr-address.sh resolve-thread --thread-id "<PRRT_threadNodeId>"
   ```
</sub-step>

<sub-step name="Review bodies and top-level comments (reply → mark addressed)">
These have no native resolution mechanism. Post a top-level comment with a machine-readable marker:

```bash
~/.cursor/skills/pr-address/scripts/pr-address.sh mark-addressed \
  --owner <OWNER> --repo <REPO> --pr <NUMBER> \
  --type <review|comment> --target-id <NUMERIC_ID> \
  --body "<what was fixed>"
```

The script appends `<!-- addressed:review:ID -->` or `<!-- addressed:comment:ID -->` to the body. Subsequent `fetch` calls detect these markers and exclude already-addressed items.

**Skip bot-only no-op items**: If a review body or top-level comment is from a bot user (e.g., `cursor`, `chatgpt-codex-connector`) AND contains no inline threads with actionable suggestions — only a summary or status message — do NOT post a `mark-addressed` comment. Human reviewer items must always be addressed or rejected, even terse ones like "This needs work".
</sub-step>

<sub-step name="Reply guidelines">
- **Addressed**: State what was fixed. Factual, 1 sentence.
- **Invalid/false-positive**: Brief evidence citing code paths or logic. 1-3 sentences.
- No pleasantries. Factual tone only.
</sub-step>
</step>

<step id="4" name="Autosquash (only when no external human reviewers)">
Only autosquash if `hasHumanReviewers` is `false`. This means no external human reviewer (someone other than `currentUser`) has commented.

Autosquash is **allowed** when only:
- Automated reviewers (`cursor`, `chatgpt-codex-connector`, or other bots) commented, OR
- `currentUser` commented (your own notes/action items)

Autosquash is **blocked** when:
- Any external human reviewer has commented — they are actively reviewing and need to see the fixup commits

If `hasHumanReviewers` is `true`, **do NOT autosquash**. Leave fixup commits visible for human reviewers to verify before squashing on merge.

When autosquashing is allowed:
```bash
~/.cursor/skills/pr-address/scripts/pr-address.sh autosquash
```

If conflicts occur, resolve them, then: `GIT_EDITOR=true git rebase --continue`. If a commit becomes empty after squashing: `git rebase --skip`.

Force push is required after autosquash because the rebase rewrites history:
```bash
git push --force-with-lease
```
</step>

<step id="5" name="Verification">
Run full verification to catch issues introduced by fixup commits:

```bash
~/.cursor/skills/verify-repo.sh . --base <upstream-ref>
```

Where `<upstream-ref>` is `origin/develop` for `edge-react-gui` or `origin/master` for other repos. Set `block_until_ms: 120000`.

If verification fails, fix the issue with another fixup commit, then re-run verification.
</step>

<step id="6" name="Post-processing">
Propose modifications to `~/.cursor/rules/typescript-standards.mdc` to prevent similar review comments in the future. Prompt for confirmation before applying.
</step>

<edge-cases>
<case name="No gh auth">Script exits code 2 with `PROMPT_GH_AUTH`. Prompt user to run `gh auth login` and STOP.</case>
<case name="No unresolved feedback">Report "No unresolved comments on this PR" and STOP.</case>
<case name="External human reviewer comments">Do NOT autosquash when `hasHumanReviewers` is true. Leave fixup commits for the external reviewer to verify, then squash on merge.</case>
<case name="Comment already addressed in code">If the current code already handles the feedback (e.g., from a previous fixup), still reply explaining this and resolve/mark the comment. Do not leave it unresolved.</case>
<case name="Already resolved thread needs follow-up">Fetch the thread history first. If the prior reply no longer reflects the latest fix, post one additional factual follow-up reply. Do not edit or delete prior replies in this workflow.</case>
</edge-cases>
