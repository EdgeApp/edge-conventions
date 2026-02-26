---
name: pr-create
description: End-to-end flow: resolve an Asana task, implement it, then create a PR with Asana linking and assignment. Use when the user wants to create a pull request.
compatibility: Requires git, gh, node, jq. ASANA_TOKEN for Asana integration.
metadata:
  author: j0ntz
---

<goal>End-to-end flow: resolve an Asana task, implement it (or continue from a prior `/im` run), then create a PR with Asana linking and assignment.</goal>

<rules description="Non-negotiable constraints.">
<rule id="use-companion-script">Do NOT call `gh` or `curl` directly. Use `scripts/pr-create.sh` for PR creation (it uses `gh` internally).</rule>
<rule id="no-script-bypass">If a companion script fails, report the error and STOP. Do NOT fall back to raw `gh`, `curl`, or other workarounds.</rule>
<rule id="gh-auth-required">If any script exits code 2 with `PROMPT_GH_AUTH`, prompt the user to run `gh auth login` and STOP.</rule>
<rule id="commit-script">Always commit using `~/.cursor/skills/lint-commit.sh -m "message" [files...]`. Never use raw `git add` + `git commit`.</rule>
<rule id="changelog-required">Every PR needs a CHANGELOG entry in the last feature commit. See `im.md` for placement rules.</rule>
<rule id="no-force-push">Do NOT force-push without explicit user confirmation.</rule>
<rule id="no-dirty-pr">Do NOT create a PR if there are uncommitted changes — commit first.</rule>
<rule id="no-base-push">Do NOT push to master/develop directly.</rule>
<rule id="asana-required">An Asana task link is always required — it provides task context for linking, PR description enrichment, and CHANGELOG placement.</rule>
<rule id="script-timeouts">Asana scripts (`asana-attach-pr.sh`, `asana-get-context.sh`) can take up to 90s. Always set `block_until_ms: 120000` when invoking them to avoid unnecessary backgrounding and polling.</rule>
</rules>

<step id="1" name="Resolve target repo and task context">
Follow `task-review.md` steps 1-3 (skip step 4 — no confirmation needed). This fetches task context, determines the target repo, and presents a brief summary.

**`cd` to the target repo before continuing.** If the task spans multiple repos, note the additional repos in the final report but do not block.
</step>

<step id="2" name="Assess state and branch">
Gather state in parallel:

```bash
git status
git rev-parse --abbrev-ref HEAD
git log --oneline -10
```

Compare the current branch's work (commit messages, CHANGELOG entries, changed files) against the Asana task name/description.

- **Match** (e.g. following a prior `/im` run): The branch already has work for this task. Skip to step 4 (push & PR).
- **Unstaged/staged changes on a feature branch**: The user already made the code change. Do NOT explore the codebase to understand the change — run `git diff` once for PR description context, commit with `lint-commit.sh`, add a CHANGELOG entry commit, then skip to step 4.
- **Mismatch**: The current branch is unrelated old work. Proceed to step 3 (branch setup & implementation).
- **On the base branch** (`develop` for `edge-react-gui`, `master` for others): Proceed to step 3 (branch setup & implementation).
</step>

<step id="3" name="Branch setup and implementation">
This step runs only when the current branch does NOT match the Asana task.

**Read `~/.cursor/skills/im/SKILL.md` now** (use the Read tool — do NOT skip this). Then follow its steps 1-3 (branch setup, pre-change lint check, implementation) using the Asana task context from step 1.

`im.md` contains the full rules for branch naming, lint-before-change, commit practices, CHANGELOG placement, and `edge-react-gui`-specific requirements. The summary below is a quick reference — `im.md` is authoritative when details differ.

Quick reference:
1. **Stash** any uncommitted changes: `git stash -u`
2. **Switch** to the base branch (`develop` for `edge-react-gui`, `master` for others), then create a new feature branch: `$GIT_BRANCH_PREFIX/<short-description>` or `$GIT_BRANCH_PREFIX/fix/<short-description>` for bug fixes.
3. **Pre-change lint check**: Run `eslint --quiet` on files before modifying. Fix pre-existing lint in a separate commit.
4. **Implement** the task with clean commits using `lint-commit.sh`. Include a CHANGELOG entry in the last commit (see `im.md` CHANGELOG placement rules).
5. New string literals in `edge-react-gui` go in `en_US.ts` in the SAME commit that uses them.

**Branch setup (sub-steps 1-2) MUST execute before any implementation-specific work** — including downloading attachments, exploring the codebase, or building todo/task lists.

After implementation, continue to step 4.
</step>

<step id="4" name="Push branch">
```bash
git push -u origin HEAD
```

If the branch already tracks a remote and is up to date, skip.
</step>

<step id="5" name="Verification">
Run full verification before creating the PR:

```bash
~/.cursor/skills/verify-repo.sh . --base <upstream-ref>
```

Where `<upstream-ref>` is `origin/develop` for `edge-react-gui` or `origin/master` for other repos. Set `block_until_ms: 120000`.

**CHANGELOG check:** Before running verification, read the top ~50 lines of `CHANGELOG.md` and confirm that entries exist which reflect the branch's changes. If no matching entries exist, add them now (see `im.md` CHANGELOG placement rules).

If verification fails, fix the issue, amend or fixup the relevant commit, push again, then continue.
</step>

<step id="6" name="Build PR description">
Gather context in parallel:

```bash
# Detect default branch
DEFAULT_BRANCH=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|origin/||' || git remote show origin 2>/dev/null | sed -n '/HEAD branch/s/.*: //p' || echo master)

# All commit messages on this branch
git log origin/$DEFAULT_BRANCH..HEAD --format=%B---
```

<sub-step name="PR title">
- **Single commit**: Use the commit message title.
- **Multiple commits**: Derive from branch name or Asana task title. Ask user if unclear.
</sub-step>

<sub-step name="PR body">
Use the repo's PR template structure. All repos share:

```markdown
### CHANGELOG

Does this branch warrant an entry to the CHANGELOG?

- [x] Yes  (or [ ] No — based on whether CHANGELOG.md was modified)
- [ ] No

### Dependencies

<!-- List dependent PRs, or "none" -->

### Description

<!-- Describe changes -->
```

**`edge-react-gui` only** — append:

```markdown
### Requirements

If you have made **any** visual changes to the GUI. Make sure you have:

- [ ] Tested on iOS device
- [ ] Tested on Android device
- [ ] Tested on small-screen device (iPod Touch)
- [ ] Tested on large-screen device (tablet)
```
</sub-step>

<sub-step name="Description content">
- If user provided a description during the session, use it.
- If single commit with a body, use the commit body.
- If multiple commits, summarize the changes.
- Include relevant technical explanation from the conversation.
</sub-step>

<sub-step name="Asana context enrichment">
If Asana context was fetched:

- **Title**: Align the PR title with the task name if it's descriptive.
- **Dependencies**: Cross-reference with linked PRs mentioned in task comments.
- **Context subsection**: Add a `#### Context` subsection at the **beginning** of the Description section — what the task is, why it matters, key decisions from comments. Wrap file paths, function names, and code references in backticks. The Asana link itself is injected by `pr-create.sh` via `--asana-task` — do not duplicate it here.

Example:

```markdown
#### Context

"gui: Token list not updating after add" (P2). The `useTokenList` hook
caches stale data because `useSyncEffect` doesn't re-trigger on `currencyConfig` changes.

#### Changes

- Fixed `useTokenList` dependency array...
```
</sub-step>

<sub-step name="Dependencies detection">
- Check if branch has `future!` commits indicating dependencies on other branches.
- If dependent PRs exist, list them with links.
</sub-step>
</step>

<step id="7" name="Create PR">
Create the PR immediately — do not ask for confirmation.

1. **Write the body to a temp file** using the **Write tool** (NOT ApplyPatch, NOT a shell command):
   - Path: `/tmp/pr-body.md`
   - Content: the full PR body built in step 6
   - The Write tool **overwrites** the file. ApplyPatch `Add File` may append to an existing file, causing stale content from a prior PR to bleed through. **Always use Write.**
2. **Run the script**:
   ```bash
   scripts/pr-create.sh --title "<title>" --body-file /tmp/pr-body.md --asana-task <task_gid>
   ```
   - Pass `--asana-task <task_gid>` when an Asana task is available. The script injects a clickable Asana link into the PR body if one isn't already present. This is **required** for downstream `/pr-land` to extract the task GID.
   - The script cleans up `/tmp/pr-body.md` after use to prevent cross-PR contamination. It will be re-populated from GitHub if needed during `/pr-address`.

Using `--body-file` avoids shell escaping issues with multi-line content. Do NOT use `--body` with inline content.

If the script exits code 2 with `PROMPT_GH_AUTH`, prompt the user to run `gh auth login` and STOP.
</step>

<step id="8" name="Link to Asana task">
If no Asana link was provided, skip silently.

```bash
scripts/asana-attach-pr.sh \
  --task <task_gid> \
  --pr-url <pr_url> \
  --pr-title "<title>" \
  --pr-number <number>
```

<sub-step name="Assignment">
By default, the script only attaches — no assignment or status change.

- If the user passed `--assign` to `/pr-create`, add `--assign` to the script call.
- If `--assign` was NOT passed, ask: "Assign this task to the reviewer? (yes/no)"
- If yes, re-run with `--assign`.
</sub-step>

<sub-step name="Handling missing fields">
With `--assign`, the script exits code 2 and outputs `PROMPT_REVIEWER` if the Reviewer field is empty. Ask the user who to assign using the team roster, then re-run with the override:

```bash
scripts/asana-attach-pr.sh \
  --task <task_gid> --pr-url <pr_url> --pr-title "<title>" --pr-number <number> \
  --assign --reviewer <user_gid>
```

The Implementor field auto-resolves to the current user (via `asana-whoami.sh`) when empty — no prompt needed. Pass `--implementor <gid>` only to override this.
</sub-step>

<sub-step name="Team roster (Asana user GIDs)">
When presenting this roster to the user, use a numbered list (not a table) to avoid rendering issues:

- Jon Tzeng — `1200972350160586`
- William Swanson — `10128869002320`
- Paul Puey — `9976421903322`
- Sam Holmes — `1198904591136142`
- Matthew Piche — `522823585857811`
</sub-step>
</step>

<step id="9" name="Report result">
Display the PR URL as a clickable markdown link: `[owner/repo#123](https://github.com/owner/repo/pull/123)`.
</step>

<edge-cases>
<case name="Branch already has an open PR">The script detects this and errors. Report the existing PR URL to the user.</case>
<case name="No gh auth">Script exits code 2 with `PROMPT_GH_AUTH`. Prompt user to run `gh auth login` and STOP.</case>
<case name="Rebase needed">If the branch is behind the default branch, ask user whether to rebase first:

```bash
git fetch origin
git rebase origin/<default-branch>
git push --force-with-lease
```
</case>
</edge-cases>