---
name: pr-land
description: Land approved PRs by autosquashing fixups, rebasing onto the default upstream branch, and merging. Use when the user wants to merge/land pull requests.
compatibility: Requires git, gh, node, jq. ASANA_TOKEN for Asana updates.
metadata:
  author: j0ntz
---

<goal>Land approved PRs on `$GIT_BRANCH_PREFIX/*` branches by autosquashing fixups, rebasing onto the default upstream branch, and pushing.</goal>

<usage>
```
/pr-land                           # All EdgeApp repos with $GIT_BRANCH_PREFIX/* PRs
/pr-land edge-react-gui            # Specific repo
/pr-land edge-react-gui edge-core-js  # Multiple repos
```
</usage>

<rules description="Non-negotiable constraints.">
<rule id="scripts-only">All GitHub API calls go through companion scripts that use `gh` CLI internally. Do NOT call `gh` or `curl` directly for GitHub operations — use the scripts.</rule>
<rule id="gh-auth">If a script exits code 2 with `PROMPT_GH_AUTH`, prompt the user to run `gh auth login`.</rule>
<rule id="code-conflicts">Code conflicts → Skip PR. Abort the rebase to leave the repo clean, continue with remaining PRs. Report all skipped PRs at the end.</rule>
<rule id="stale-prs">Stale PRs → Skip and report. Old PRs with multiple conflicts should be skipped like code conflicts. Don't block the flow.</rule>
<rule id="changelog-conflicts">CHANGELOG conflicts (any section, including staging): Agent resolves semantically, scripts verify the result.</rule>
<rule id="verification">Verification is mandatory. Built into scripts, no bypass.</rule>
<rule id="no-force-push">Do NOT force-push without explicit user confirmation.</rule>
<rule id="no-editors">Never open editors. All git operations must be non-interactive: `GIT_EDITOR=true` for commit messages, `GIT_SEQUENCE_EDITOR=:` for rebase todo lists.</rule>
<rule id="unexpected-exit">Unexpected exit codes → STOP immediately. If any script returns an exit code not documented in this file, STOP and report to user. Do NOT attempt to interpret, retry, or work around unexpected errors.</rule>
<rule id="sequential-rebase">Sequential merging requires rebase. Each subsequent PR MUST be rebased onto the updated base branch after the previous merge.</rule>
<rule id="publish-gating">Don't publish if outstanding PRs remain. Only offer to publish a repo when ALL approved PRs for that repo are merged. If any were skipped or held back, do NOT publish that repo.</rule>
<rule id="npm-publish-gate">Step 7 CANNOT begin until the user explicitly confirms npm publish succeeded. `npm publish` requires interactive 2FA — the agent cannot run it. Do NOT infer publish completion from git push or tagging. STOP and WAIT for user confirmation.</rule>
<rule id="asana-last">Asana updates are LAST. Do NOT update Asana tasks until ALL merges, publishes, and GUI dependency upgrades are complete. Only update status for PRs that are fully landed (merged, and if non-GUI: published + GUI deps updated).</rule>
</rules>

<scripts description="Companion scripts and their expected exit codes.">

| Script | Purpose |
|--------|---------|
| `pr-land-discover.sh` | Discover PRs and approval status |
| `pr-land-comments.sh` | Check for recent unaddressed feedback (inline threads, review bodies, top-level comments) |
| `pr-land-prepare.sh` | Rebase + conflict detection + verification |
| `verify-repo.sh` | Verification (CHANGELOG + code; lint scoped to changed files when `--base` given) |
| `pr-land-merge.sh` | Rebase + verify + merge via GitHub API |
| `pr-land-publish.sh` | Version bump, changelog update, commit + tag (no push) |
| `asana-task-update.sh` | Update linked Asana tasks after merge |

| Script | Exit 0 | Exit 1 | Exit 2 | Exit 3 | Exit 4 |
|--------|--------|--------|--------|--------|--------|
| `pr-land-discover.sh` | Success | Error | - | - | - |
| `pr-land-comments.sh` | Success | Error | - | - | - |
| `pr-land-prepare.sh` | Ready | All failed | - | - | - |
| `verify-repo.sh` | Pass | Code fail | CHANGELOG fail | - | - |
| `pr-land-merge.sh` | Merged | Verify fail | - | - | CHANGELOG conflict |
| `pr-land-publish.sh` | Ready (needs push) | Verify fail | No unreleased | - | - |
| `asana-task-update.sh` | Success | Error | Needs user input | - | - |

**Any exit code not in this table = STOP immediately and report to user.**
</scripts>

<step id="1" name="Discovery">
ONE tool call:

```bash
scripts/pr-land-discover.sh [repo1 repo2 ...]
```

Returns JSON with all `$GIT_BRANCH_PREFIX/*` PRs and their approval status.
</step>

<step id="2" name="Comment Check and Addressing">
```bash
echo '[{"repo":"...","prNumber":123,"branch":"<prefix>/..."}]' | scripts/pr-land-comments.sh
```

Returns PRs with unaddressed feedback posted after the last commit. The script checks **three sources**:

1. **Unresolved inline review threads** — threads where `isResolved: false` with comments newer than last commit
2. **Review bodies** — the latest review from each non-author/non-bot reviewer, if it has a non-empty body newer than last commit (catches feedback written in the approve/reject dialog, regardless of review state)
3. **Top-level PR comments** — non-author/non-bot comments newer than last commit

Items previously marked with `<!-- addressed:review:ID -->` or `<!-- addressed:comment:ID -->` markers are automatically excluded.

<sub-step name="Comment handling">
1. AI/bot comments: Already filtered out by the script.
2. Human reviewer comments on approved PRs — address and set aside:
   1. Read the comment and understand the requested change
   2. Make the fix as a fixup commit: `~/.cursor/skills/lint-commit.sh --fixup <hash> [files...]`
   3. Push the fixup to the branch
   4. Reply on the PR thread explaining what was fixed (1 sentence, factual). Use `gh pr comment <number> --repo EdgeApp/<repo> --body "..."` for top-level comments, or reply to the specific thread if the feedback was inline.
   5. **Remove this PR from the merge set** — it needs re-review after the fixup
   6. Continue with remaining PRs that have no outstanding comments
   7. Report addressed PRs to the user at the end of the workflow

**Do NOT block the rest of the flow** for PRs with comments.
</sub-step>
</step>

<step id="3" name="Prepare Branches">
ONE tool call per batch:

```bash
echo '[{"repo":"...","branch":"<prefix>/feature"}]' | scripts/pr-land-prepare.sh
```

The prepare script handles: clone/checkout, autosquash fixups, rebase onto upstream, conflict detection, and verification.

**Exit codes:**
- `0` = At least one PR ready to push (skipped PRs reported in JSON output)
- `1` = All PRs failed (verification or other errors, none ready)

<sub-step name="On code conflict">PR is skipped and reported in the `skipped` array. Rebase is aborted to leave repo clean. Other PRs continue.</sub-step>

<sub-step name="On CHANGELOG conflict">Agent resolves semantically (upstream entries first, then ours), then re-runs prepare.</sub-step>
</step>

<step id="4" name="Push">
After prepare succeeds, push with `--force-with-lease`.
</step>

<step id="5" name="Merge">
Ask for user confirmation, then:

```bash
echo '[{"repo":"...","prNumber":123,"branch":"<prefix>/..."}]' | scripts/pr-land-merge.sh [method]
```

The merge script processes PRs **sequentially** with automatic rebase-before-merge:

1. **Check if already merged** — skip (handles re-runs after CHANGELOG resolution)
2. **Fetch + rebase onto upstream** — ALWAYS done, even for first PR
3. **Conflict handling during rebase:**
   - No conflict → continue
   - CHANGELOG-only (any section) → **exit 4** (agent resolves, re-runs)
   - Code conflict → **skip PR**, abort rebase, continue
4. **Push `--force-with-lease`**
5. **Run local verification** (MANDATORY)
6. **Merge via GitHub API**

**Exit codes:**
- `0` = All (non-skipped) PRs merged
- `1` = Verification failed
- `4` = CHANGELOG-only conflict (agent resolves, re-runs)

**On exit 4:** Agent resolves semantically, pushes, re-runs merge. Script detects already-merged PRs and skips them.
</step>

<step id="6" name="Publish">
**Gating:** Only non-GUI repos. Only when ALL approved PRs for the repo are merged. Skip if any were skipped/held back.

Ask for user confirmation:
```
Merged repos ready to publish (all PRs landed):
  - <repo> (<branch>)

Repos with outstanding PRs (not ready to publish):
  - <repo> (N PRs skipped)

Publish ready repos to npm? [y/N]
```

If confirmed:

```bash
echo '[{"repo":"...","branch":"master"}]' | scripts/pr-land-publish.sh
```

**Exit codes:**
- `0` = Version bumped, committed, tagged (check `needsPush` in JSON output)
- `1` = Verification failed
- `2` = No unreleased changes in CHANGELOG

After script completes:
1. Show version bump details to user
2. If confirmed, push master and tag: `git push origin master && git push origin v<version>`
3. Prompt user to run `npm publish` in a real terminal (requires interactive 2FA)

**STOP HERE. Do NOT proceed to step 7 until the user confirms npm publish succeeded.**
</step>

<step id="7" name="Update GUI Dependencies">
**Trigger:** Only if non-`edge-react-gui` repos were merged and published in steps 5–6.

Ask user to confirm `npm publish` completed, then:

1. Save current branch and switch to develop:
   ```bash
   cd <gui-repo-dir>
   ORIG_BRANCH=$(git rev-parse --abbrev-ref HEAD)
   git checkout develop && git pull origin develop
   ```

2. Run `upgrade-dep.sh` for each published package (sequentially):
   ```bash
   cd <gui-repo-dir> && scripts/upgrade-dep.sh <package-name>
   ```
   If any fails, STOP and report. Ask user how to proceed.

3. Restore original branch:
   ```bash
   cd <gui-repo-dir>
   git checkout $ORIG_BRANCH
   git stash pop
   ```
   If stash pop fails with conflicts, STOP and report. If "No stash entries", that's fine.
</step>

<step id="8" name="Update Asana Tasks">
**Runs ONLY after ALL merges, publishes, and GUI dep upgrades are complete.**

Only update for fully landed PRs:
- GUI PRs: merged
- Non-GUI PRs: merged AND published AND GUI deps updated

Do NOT update for: skipped PRs, addressed-but-not-re-reviewed PRs, or repos not published.

<sub-step name="Extract Asana task GIDs">
Pipe the PR metadata through the new helper so you only consume the Asana link once per PR:

```bash
printf '[{"repo":"edge-react-gui","prNumber":123}]' | scripts/pr-land-extract-asana-task.sh > /tmp/asana.json
```

The helper outputs JSON like `{ "tasks": [{ "taskGid": "...", "label": "repo#123" }], "missing": [{ "label": "...", "reason": "..." }] }`.
Review the `missing` array, report any entries lacking an Asana link, and skip those PRs for Asana updates.
</sub-step>

<sub-step name="Update tasks">
For each task in `.tasks`, run:

```bash
~/.cursor/skills/asana-task-update/scripts/asana-task-update.sh \
  --task <task_gid> \
  --set-status "Verification Needed" \
  --unassign
```

This replaces the old dedicated verification updater behavior.

**Exit codes per call:**
- `0` = success
- `1` = error
- `2` = needs user input
</sub-step>
</step>

<step id="9" name="End-of-Workflow Report">
```
=== PR Land Summary ===

Fully landed:
  ✓ <repo>#<number> (<branch>) — merged, Asana updated
  ✓ <repo>#<number> (<branch>) — merged, published v<version>, GUI deps updated, Asana updated

Addressed but needs re-review:
  ⚠ <repo>#<number> (<branch>) — fixup pushed, awaiting review

Skipped (conflicts):
  ⚠ <repo>#<number> (<branch>) — stale / code conflict in <file>

Not published (outstanding PRs):
  ⚠ <repo> — N PRs skipped, publish deferred
```
</step>

<conflict-handling description="Summary of conflict types and resolution.">

| Conflict Type | Script Behavior | Agent Action |
|---|---|---|
| Code files | Skip PR, abort rebase, continue | Report to user at end |
| CHANGELOG only (prepare) | Report conflict | Resolve semantically, re-run prepare |
| CHANGELOG only (merge) | **exit 4** with instructions | Resolve semantically, push, re-run merge |

Both prepare and merge scripts can detect CHANGELOG-only conflicts. In either case:
1. Script outputs clear resolution instructions
2. Agent resolves semantically (upstream entries first)
3. `git add CHANGELOG.md && GIT_EDITOR=true git rebase --continue`
4. Push with `--force-with-lease`
5. Re-run the script to verify and proceed
</conflict-handling>

<changelog-resolution description="How the agent resolves CHANGELOG conflicts.">
```
# Typical conflict:
<<<<<<< HEAD
- added: Feature from upstream
=======
- changed: Our feature
>>>>>>> our-commit

# Resolution: Upstream first, then ours:
- added: Feature from upstream
- changed: Our feature
```

<sub-step name="During prepare (no push yet)">
1. Read CHANGELOG.md with conflict markers
2. Resolve semantically using StrReplace
3. `git add CHANGELOG.md && GIT_EDITOR=true git rebase --continue`
4. Re-run `pr-land-prepare.sh`
</sub-step>

<sub-step name="During merge (already pushed, GitHub reports conflict)">
1. `cd <repoDir>`
2. `git fetch origin && git rebase origin/master` (or `origin/develop`)
3. Read CHANGELOG.md with conflict markers
4. Resolve semantically using StrReplace
5. `git add CHANGELOG.md && GIT_EDITOR=true git rebase --continue`
6. `git push --force-with-lease`
7. Re-run `pr-land-merge.sh` — verification runs automatically
</sub-step>

Verification checks: no conflict markers remaining, proper entry format (`- type: description`), no malformed entries. If verification fails after resolution, the script prompts the user.
</changelog-resolution>

<safety-guarantees>
1. Code conflicts skip cleanly — scripts abort rebase and skip, no dirty state
2. CHANGELOG conflicts are scripted — agent resolves semantically (any section including staging), verification validates
3. Verification is mandatory — built into merge script, physically blocks merge on failure
4. Pre-merge is safe — can force-push as many times as needed
5. Sequential merging with auto-rebase — each PR rebased onto updated base
6. No bypasses — scripts enforce rules, agent cannot skip steps
7. Unexpected errors halt execution — undocumented exit codes stop immediately
8. Publish gating — repos with outstanding PRs are not published
9. Asana is last — task updates only after full pipeline completes
</safety-guarantees>
