# pr-land

## Goal
Land approved PRs on `$GIT_BRANCH_PREFIX/*` branches by autosquashing fixups, rebasing onto the default upstream branch, and pushing.

## Usage

```
/pr-land                           # All EdgeApp repos with $GIT_BRANCH_PREFIX/* PRs
/pr-land edge-react-gui            # Specific repo
/pr-land edge-react-gui edge-core-js  # Multiple repos
```

## Hard rules (non-negotiable)

- All GitHub API calls go through companion scripts that use `gh` CLI internally. Do NOT call `gh` or `curl` directly for GitHub operations — use the scripts.
- If a script exits code 2 with `PROMPT_GH_AUTH`, prompt the user to run `gh auth login`.
- **Code conflicts → Skip PR**: Skip the conflicting PR, abort the rebase to leave the repo clean, and continue with remaining PRs. Report all skipped PRs at the end.
- **Stale PRs → Skip and report**: Old PRs with multiple conflicts should be skipped like code conflicts. Don't block the flow.
- **CHANGELOG conflicts**: Agent resolves semantically, scripts verify the result.
- **Staging section conflicts**: STOP and prompt user for guidance (workflow refinement needed).
- **Verification is mandatory**: Built into scripts, no bypass.
- I will **NOT** force-push without explicit user confirmation.
- **Never open editors**: All git operations must be non-interactive:
  - `GIT_EDITOR=true` - prevents editor for commit messages
  - `GIT_SEQUENCE_EDITOR=:` - prevents editor for rebase todo list
- **Unexpected exit codes → STOP immediately**: If any script returns an exit code not documented in this file, I will STOP and report the error to the user. I will NOT attempt to interpret, retry, or work around unexpected errors.
- **Sequential merging requires rebase**: When merging multiple PRs in the same repo, each subsequent PR MUST be rebased onto the updated base branch after the previous merge. This is always necessary — do not attempt to merge without rebasing first.
- **Don't publish if outstanding PRs remain**: Only offer to publish a repo when ALL approved PRs for that repo are merged. If any were skipped or held back, do NOT publish that repo.
- **Asana updates are LAST**: Do NOT update Asana tasks until ALL merges, publishes, and GUI dependency upgrades are complete. Only update status for PRs that are fully landed (merged, and if non-GUI: published + GUI deps updated).

## Scripts

| Script | Purpose |
|--------|---------|
| `pr-land-discover.sh` | Discover PRs and approval status |
| `pr-land-comments.sh` | Check for recent comments |
| `pr-land-prepare.sh` | **Rebase + conflict detection + verification** |
| `verify-repo.sh` | Verification (CHANGELOG + code; lint scoped to changed files when `--base` given) |
| `pr-land-merge.sh` | Rebase + verify + merge via GitHub API |
| `pr-land-publish.sh` | Version bump, changelog update, commit + tag (no push) |
| `asana-verification-needed.sh` | Update linked Asana tasks after merge |

## Expected Exit Codes (all others → STOP)

| Script | Exit 0 | Exit 1 | Exit 2 | Exit 3 | Exit 4 |
|--------|--------|--------|--------|--------|--------|
| `pr-land-discover.sh` | Success | Error | - | - | - |
| `pr-land-comments.sh` | Success | Error | - | - | - |
| `pr-land-prepare.sh` | Ready | All failed | - | Staging conflict | - |
| `verify-repo.sh` | Pass | Code fail | CHANGELOG fail | - | - |
| `pr-land-merge.sh` | Merged | Verify fail | - | Staging conflict | CHANGELOG conflict |
| `pr-land-publish.sh` | Ready (needs push) | Verify fail | No unreleased | - | - |
| `asana-verification-needed.sh` | All updated | Partial failure | Missing ASANA_TOKEN/input | - | - |

**Any exit code not in this table = STOP immediately and report to user.**

## Complete Workflow

### Phase 1: Discovery (ONE tool call)

```bash
~/.cursor/commands/pr-land-discover.sh [repo1 repo2 ...]
```

Returns JSON with all `$GIT_BRANCH_PREFIX/*` PRs and their approval status.

### Phase 2: Comment Check and Addressing

```bash
echo '[{"repo":"...","prNumber":123,"branch":"<prefix>/..."}]' | ~/.cursor/commands/pr-land-comments.sh
```

Returns PRs with comments posted after last commit.

**Comment handling:**
- **AI/bot comments**: Ignore — these are not actionable.
- **Human reviewer comments on approved PRs**: Assume the change is simple enough to address. The agent should:
  1. Read the comment and understand the requested change
  2. Make the fix as a fixup commit using `~/.cursor/commands/lint-commit.sh --fixup <hash> [files...]`
  3. Push the fixup to the branch
  4. **Remove this PR from the merge set** — it needs re-review after the fixup
  5. Continue with remaining PRs that have no outstanding comments
  6. Report addressed PRs to the user at the end of the workflow

**Do NOT block the rest of the flow** for PRs with comments. Address and set aside.

### Phase 3: Prepare Branches (ONE tool call per batch)

```bash
echo '[{"repo":"edge-react-gui","branch":"<prefix>/feature"}]' | ~/.cursor/commands/pr-land-prepare.sh
```

The prepare script handles:
1. Clone/checkout repo
2. Autosquash fixup commits
3. Rebase onto upstream (origin/master or origin/develop)
4. **Conflict detection** (scripted, deterministic):
   - Code conflicts → **Skip PR**, abort rebase, continue with remaining PRs
   - Staging section conflict → **exit 3** (STOP - user guidance needed)
   - CHANGELOG-only conflict → reports it for agent to resolve semantically
5. Run verification (CHANGELOG + prepare/tsc/lint/test)

**Exit codes:**
- `0` = At least one PR ready to push (skipped PRs reported in JSON output)
- `1` = All PRs failed (verification or other errors, none ready)
- `3` = Staging section conflict (STOP)

**On code conflict:** The PR is skipped and reported in the `skipped` array in the output JSON. The rebase is aborted to leave the repo in a clean state. Other PRs continue processing.

**On CHANGELOG conflict:**
Agent resolves semantically (upstream entries first, then ours), then re-runs prepare.

### Phase 4: Push

After prepare succeeds, push with `--force-with-lease`.

### Phase 5: Merge (sequential with automatic rebase)

Ask for user confirmation to merge:

```bash
echo '[{"repo":"...","prNumber":123,"branch":"<prefix>/..."}]' | ~/.cursor/commands/pr-land-merge.sh [method]
```

The merge script processes PRs **sequentially** and handles the rebase-before-merge pattern automatically:

For each PR:
1. **Check if already merged** — skip if so (handles re-runs after CHANGELOG resolution)
2. **Fetch + rebase onto upstream** — This is ALWAYS done, even for the first PR, because the base branch may have changed since prepare. For subsequent PRs in the same repo, this picks up changes from the prior merge.
3. **Conflict handling during rebase:**
   - No conflict → continue
   - CHANGELOG-only conflict → **exit 4** (agent resolves, re-runs)
   - Code conflict → **skip PR**, abort rebase, continue with remaining PRs
   - Staging section conflict → **exit 3** (STOP)
4. **Push `--force-with-lease`** — after successful rebase
5. **Run local verification** (MANDATORY - no bypass)
6. **Merge via GitHub API**

**Exit codes:**
- `0` = All (non-skipped) PRs merged
- `1` = Verification failed
- `3` = Staging section conflict (STOP - needs workflow guidance)
- `4` = CHANGELOG-only conflict (agent resolves semantically, then re-runs)

**On CHANGELOG conflict (exit 4):** Agent resolves semantically, pushes, re-runs merge. The script detects already-merged PRs and skips them, resuming from where it left off.

### Phase 6: Publish

**Gating:** Only relevant to non-GUI repos. Only offer to publish a repo when **ALL** approved PRs for that repo have been merged. If any PRs were skipped (due to conflicts, comments, staleness), do NOT publish that repo.

Ask for user confirmation to publish:

After merge completes, for each non-`edge-react-gui` repo where ALL PRs are merged:

**Agent prompts:**
```
Merged repos ready to publish (all PRs landed):
  - edge-exchange-plugins (master)
  - edge-currency-accountbased (master)

Repos with outstanding PRs (not ready to publish):
  - edge-core-js (1 PR skipped due to conflict)

Publish ready repos to npm? [y/N]
```

If user confirms:

```bash
echo '[{"repo":"edge-exchange-plugins","branch":"master"}]' | ~/.cursor/commands/pr-land-publish.sh
```

The publish script:
1. Resets to origin/master
2. Parses CHANGELOG.md for unreleased entries
3. Runs verification (yarn verify or yarn tsc && yarn lint)
4. Bumps version (minor for added/changed, patch for fixed only)
5. Updates CHANGELOG.md with version header and date
6. Commits `v{version}` and tags locally (**does NOT push**)
7. Returns JSON with `needsPush` flag

After the script completes, the agent:
1. Shows the user the version bump details (version, changelog entries)
2. Asks user to confirm the changes look correct
3. If confirmed, agent pushes master and tag to origin:
   ```bash
   cd <repoDir>
   git push origin master && git push origin v<version>
   ```
4. Prompts the user to run `npm publish` in a real terminal:
   ```
   Run in a terminal:
     cd <repoDir>
     npm publish
   ```

**Important:** `npm publish` must be run by the user in a real terminal because npm requires interactive 2FA authentication.

**Exit codes:**
- `0` = Version bumped, committed, tagged (check `needsPush` in JSON output)
- `1` = Verification failed
- `2` = No unreleased changes in CHANGELOG

### Phase 7: Update GUI Dependencies

After Phase 6 completes and the user has run `npm publish`, update the GUI's dependencies for each published package.

**Trigger:** Only if non-`edge-react-gui` repos were merged and published in Phases 5–6.

**Agent prompts:**
```
Did you complete `npm publish` for the published packages?
  - edge-exchange-plugins v1.2.3
  - edge-core-js v2.3.4

[y/N]
```

If user confirms:

1. **Save current branch and switch to `develop`:**
   ```bash
   cd <gui-repo-dir>
   ORIG_BRANCH=$(git rev-parse --abbrev-ref HEAD)
   git checkout develop && git pull origin develop
   ```

2. **Run `upgrade-dep.sh` for each published package** (sequentially):
   ```bash
   cd <gui-repo-dir> && ~/.cursor/commands/upgrade-dep.sh <package-name>
   ```
   If any invocation fails, STOP and report the error. Ask the user how to proceed before continuing with remaining packages.

3. **Restore original branch and pop stash:**
   ```bash
   cd <gui-repo-dir>
   git checkout $ORIG_BRANCH
   git stash pop
   ```
   If `git stash pop` fails with merge conflicts, STOP and report — the user has working changes that conflict with the new develop state. If it reports "No stash entries", that's fine.

### Phase 8: Update Asana Tasks (LAST STEP)

**IMPORTANT:** This phase runs ONLY after ALL of the following are complete:
- All merges (Phase 5)
- All publishes (Phase 6) for non-GUI repos
- All GUI dependency upgrades (Phase 7) for published packages

**Only update Asana for PRs that are fully landed:**
- GUI PRs: merged
- Non-GUI PRs: merged AND published AND GUI deps updated

Do NOT update Asana for:
- PRs that were skipped (conflicts, staleness)
- PRs that were addressed but not re-reviewed (comment fixups)
- PRs in repos that were not published (outstanding PRs blocked publish)

**Step 1: Extract Asana task GIDs from PR descriptions.**

For each fully-landed PR, fetch the body and extract the Asana link:

```bash
gh api "repos/EdgeApp/{repo}/pulls/{prNumber}" --jq '.body'
```

Extract the task GID from the body using the regex pattern:
`https://app.asana.com/\d+/\d+/(?:task/)?(\d+)` — capture group 1 is the task GID.

If no Asana link is found, report it to the user and skip that PR.

**Step 2: Call the script with extracted task GIDs.**

```bash
echo '[{"taskGid":"1234567890","label":"edge-react-gui#123"},{"taskGid":"9876543210","label":"edge-core-js#456"}]' | ~/.cursor/commands/asana-verification-needed.sh
```

The script is pure Asana (no GitHub dependency). For each task it:
1. Validates the task status is currently **"Publish Needed"**
2. Unsets the assignee
3. Sets status to **"Verification Needed"**

**Exit codes:**
- `0` = All tasks updated
- `1` = One or more tasks failed (see JSON output for details)
- `2` = Missing `ASANA_TOKEN` or invalid input

**On error:** Report the specific failures from the JSON output. Common issues:
- **No Asana link in PR description** → Caught in Step 1; report to user
- **Status not "Publish Needed"** → Report current status; the task may have been manually updated

Pass all fully-landed tasks in a single call.

### End-of-Workflow Report

After all phases complete, provide a summary to the user:

```
=== PR Land Summary ===

Fully landed:
  ✓ edge-react-gui#123 (<prefix>/feature-a) — merged, Asana updated
  ✓ edge-exchange-plugins#456 (<prefix>/feature-b) — merged, published v2.41.0, GUI deps updated, Asana updated

Addressed but needs re-review:
  ⚠ edge-react-gui#789 (<prefix>/some-feature) — fixup pushed, awaiting review

Skipped (conflicts):
  ⚠ edge-react-gui#101 (<prefix>/old-feature) — stale, multiple code conflicts
  ⚠ edge-core-js#202 (<prefix>/something) — code conflict in src/utils.ts

Not published (outstanding PRs):
  ⚠ edge-core-js — 1 PR skipped, publish deferred
```

## Conflict Handling Summary

| Conflict Type | Script Behavior | Agent Action |
|---------------|-----------------|--------------|
| Code files | Skip PR, abort rebase, continue | Report to user at end |
| Staging section | **STOP** (exit 3) | Report to user, ask for workflow guidance |
| CHANGELOG only (prepare) | Report conflict | Resolve semantically, re-run prepare |
| CHANGELOG only (merge) | **exit 4** with instructions | Resolve semantically, push, re-run merge |

Both prepare and merge scripts can detect CHANGELOG-only conflicts. In either case:
1. Script outputs clear resolution instructions
2. Agent resolves semantically (upstream entries first)
3. `git add CHANGELOG.md && git rebase --continue`
4. Push with `--force-with-lease`
5. Re-run the script to verify and proceed

## CHANGELOG Resolution (Agent)

When prepare or merge reports a CHANGELOG-only conflict (exit 4):

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

### During prepare (no push yet)
1. Read CHANGELOG.md with conflict markers
2. Resolve semantically using StrReplace
3. `git add CHANGELOG.md && git rebase --continue`
4. Re-run `pr-land-prepare.sh`

### During merge (already pushed, GitHub reports conflict)
1. `cd <repoDir>`
2. `git fetch origin && git rebase origin/master` (or origin/develop)
3. Read CHANGELOG.md with conflict markers
4. Resolve semantically using StrReplace
5. `git add CHANGELOG.md && git rebase --continue`
6. `git push --force-with-lease`
7. Re-run `pr-land-merge.sh` - verification will run automatically

The verification checks:
- No conflict markers remaining
- Proper entry format (- type: description)
- No malformed entries

If verification fails after agent resolution, the script prompts the user.

## Output Examples

### Prepare output (success with skipped)
```json
{
  "prepared": [
    {"repo": "edge-react-gui", "branch": "<prefix>/feature", "status": "ready"}
  ],
  "failed": [],
  "skipped": [
    {
      "repo": "edge-core-js",
      "branch": "<prefix>/old-thing",
      "status": "code_conflict",
      "conflictFiles": ["src/utils.ts"],
      "message": "Code conflict — skipped"
    }
  ],
  "changelogConflicts": [],
  "stagingConflicts": []
}
```

### Merge output (success)
```json
{
  "merged": [
    {"repo": "edge-react-gui", "prNumber": 123, "sha": "abc1234"}
  ],
  "failed": [],
  "skipped": [],
  "pending": [],
  "conflict": null,
  "verificationFailed": null,
  "status": "complete"
}
```

### Merge output (CHANGELOG conflict - agent resolves)
```json
{
  "merged": [
    {"repo": "edge-react-gui", "prNumber": 123, "sha": "abc1234"}
  ],
  "changelogConflict": {
    "repo": "edge-react-gui",
    "prNumber": 456,
    "branch": "<prefix>/feature-b",
    "repoDir": "<gui-repo-dir>",
    "conflictFiles": ["CHANGELOG.md"]
  },
  "pending": [],
  "skipped": [],
  "status": "changelog_conflict_needs_resolution"
}
```

## Safety Guarantees

1. **Code conflicts skip cleanly** - Scripts abort rebase and skip, no dirty state left behind
2. **Staging conflicts are deterministic** - Scripts detect and STOP, requires workflow guidance
3. **CHANGELOG conflicts are scripted** - Agent resolves semantically, verification script validates
4. **Verification is mandatory** - Built into merge script, physically blocks merge on failure
5. **Pre-merge is safe** - Can force-push as many times as needed to fix issues
6. **Sequential merging with auto-rebase** - Each PR is rebased onto updated base before merge
7. **No bypasses** - Scripts enforce rules, agent cannot skip steps
8. **Unexpected errors halt execution** - Any undocumented exit code stops the workflow immediately
9. **Publish gating** - Repos with outstanding PRs are not published
10. **Asana is last** - Task updates only after full pipeline completes for each PR
