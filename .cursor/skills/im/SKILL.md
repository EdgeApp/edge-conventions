---
name: im
description: Implement an Asana task or ad-hoc feature/fix with clean, structured commits. Use when the user wants to implement a task, build a feature, or fix a bug in an Edge repository.
compatibility: Requires git, gh, node, jq. ASANA_TOKEN for Asana integration.
metadata:
  author: j0ntz
---

<goal>Implement an Asana task or ad-hoc feature/fix with clean, well-structured commits.</goal>

<rules description="Non-negotiable constraints.">
<rule id="read-coding-standards">Before writing ANY code, read `.cursor/rules/typescript-standards.mdc` and follow all rules and standards in it throughout the implementation.</rule>
<rule id="no-impl-before-confirm">Do NOT begin implementation until the user confirms the `/asana-plan` output (Step 0).</rule>
<rule id="lint-before-change">Before the first edit to ANY file, run `~/.cursor/skills/im/scripts/lint-warnings.sh <files...>` to auto-fix auto-fixable lint issues, then load any remaining lint findings and matching fix patterns into context. If the script changes files or leaves findings, handle those in a separate lint-fix commit IMMEDIATELY BEFORE the commit with actual changes. This applies to every file you touch, including ones discovered mid-implementation — not just the files you planned upfront.</rule>
<rule id="no-manual-formatting">Do not manually fix formatting. `lint-commit.sh` runs `eslint --fix` (which includes Prettier) before committing. If you see a formatting lint after editing, do NOT make another edit to fix it.</rule>
<rule id="commit-script">Always commit using `~/.cursor/skills/lint-commit.sh -m "message" [files...]` or `--fixup <hash>` for fixup commits.</rule>
<rule id="generated-companion-files">When committing with scoped file arguments, treat `src/locales/strings`, `eslint.config.mjs`, and snapshot files as expected auto-generated companion files in the same commit. If `lint-commit.sh` reports additional non-generated files outside the intended scope, evaluate whether the commit plan is wrong before continuing.</rule>
<rule id="clean-history">The final commit history must read as a clean, straight-line progression — as if every decision was made correctly up front. Never preserve the "squiggly path" of development (adding then removing code, temporary scaffolding, exploratory commits). If you introduce something in commit A and remove it in commit B, restructure so the final history never contains it. Plan commits proactively to avoid this; when it happens anyway, restructure the branch before finishing.</rule>
<rule id="no-script-bypass">If a companion script fails, report the error and STOP. Do NOT fall back to raw `gh`, `curl`, or other workarounds.</rule>
<rule id="script-timeouts">`asana-get-context.sh` can take up to 90s and `install-deps.sh` can exceed 10s on repo prepare steps. Always use at least a 120000ms timeout for these scripts to avoid false failures from client-side time limits.</rule>
</rules>

<step id="0" name="Planning handoff via /asana-plan">
Always delegate planning to `~/.cursor/skills/asana-plan/SKILL.md` first:

- If user provided an Asana URL, run `/asana-plan` in Asana mode.
- If user provided ad-hoc text or file references, run `/asana-plan` in text/file mode.

`/asana-plan` returns a plan file path + short execution summary and waits for user confirmation. Start implementation only after that confirmation.

### Regression analysis

If the task describes a regression (e.g. "broke in version X", "stopped working after update"):

1. **Identify the breaking commit** using `git log`, `git bisect`, or version tag comparison. Don't take the reported version from the task at face value — verify by examining the actual commit history.
2. **Review the original change's full intent.** Find the associated PR and any linked tasks/discussions. The regression-causing commit likely had legitimate goals (performance, refactoring, new features). Understand ALL of its intended effects, not just the one that broke.
3. **Ensure the fix preserves the original intent.** The fix must not undo the beneficial changes introduced by the regression commit. If the fix conflicts with the original intent, flag this to the user with tradeoffs before proceeding.
   </step>

<step id="1" name="Branch setup">
After Step 0 determines the target repo (or if no Asana task, use the current repo):

1. **Stash any uncommitted changes** (including untracked files) before switching branches: `git stash -u`
2. Determine the correct branch state:
   - **Wrong repo**: `cd` to the correct workspace repo directory.
   - **On an unrelated feature branch**: Switch to the base branch (see "Branch from" column in `task-review.md`), then create a new feature branch.
   - **On the base branch**: Create a new feature branch.
   - **On the correct feature branch**: Continue.
3. **Branch naming**: `$GIT_BRANCH_PREFIX/<short-description>` or `$GIT_BRANCH_PREFIX/fix/<short-description>` for bug fixes. Use kebab-case. Example: `<prefix>/some-feature` or `<prefix>/fix/some-bug`
4. **Assume a new branch is needed** unless the current branch clearly matches the task. Do NOT ask for confirmation — the existing branch has its own committed work and is unaffected.
5. **Install dependencies**: After creating or switching to the feature branch, run `~/.cursor/skills/install-deps.sh` with a timeout of at least 120000ms to ensure dependencies match the base branch state without false timeout failures.

If the task spans multiple repos, note the additional repos but implement in the primary repo first.
</step>

<step id="2" name="Pre-change lint check">
**Before writing ANY code**, run `lint-warnings.sh` on every file you plan to modify:

```bash
~/.cursor/skills/im/scripts/lint-warnings.sh <file1> <file2> ...
```

This script:

1. Runs `eslint --fix`
2. Detects files that will be "graduated" from the warning suppression list on commit, promoting their suppressed-rule warnings to errors in the output
3. Shows any remaining findings grouped by rule (with graduation promotions already applied)
4. Outputs matching fix patterns from `~/.cursor/rules/typescript-standards.mdc`
5. Flags unmatched rules that need new patterns added

If the script auto-fixes files or remaining findings exist:

1. Fix all reported **errors** first — these include graduation-promoted warnings that will block `lint-commit.sh` after the file is removed from the suppression list
2. Fix remaining **warnings** using the matched patterns in the output
3. For **unmatched rules**: After fixing, add a new `<pattern id="..." rule="...">` to `typescript-standards.mdc` so future occurrences have guidance
4. Commit the pre-existing lint changes separately:
   ```bash
   ~/.cursor/skills/lint-commit.sh -m "Fix lint warnings in <ComponentName>" <file1> <file2> ...
   ```

**Architectural vs mechanical fixes**: If a pattern notes "architectural change" (e.g., `styled()` refactoring), flag to user rather than fixing inline — these changes have broader impact and may warrant separate discussion.

`lint-commit.sh` treats passed file arguments as the primary commit scope and only stages those files plus generated companion files (`src/locales/strings`, `eslint.config.mjs`, snapshots). It does not stage unrelated dirty files in the working tree.

This ensures the subsequent feature commit introduces zero pre-existing lint findings. This is the initial pass — if you discover additional files to modify during Step 3, the same check applies (see Step 3).
</step>

<step id="3" name="Implementation">
1. **Lint-check newly discovered files**: If you need to modify a file not covered in Step 2, run `~/.cursor/skills/im/scripts/lint-warnings.sh <file>` before editing it. If the script auto-fixes the file or leaves remaining pre-existing findings, commit those changes as a `--fixup` to the lint-fix commit from Step 2 (use `git log --oneline` to find the hash). If no lint-fix commit exists yet, create one.
2. Break up the feature into multiple commits if necessary. Commit messages should be a concise title without tags like "feat" and a short body.
3. Open relevant ts/tsx files before writing code.
4. Commit using `lint-commit.sh`:
   ```bash
   ~/.cursor/skills/lint-commit.sh -m "commit message" [files...]
   ```
   You can optionally pass specific files to scope the commit.
5. **Fixup commits**: When a change logically amends an earlier commit on the branch (e.g. fixing a typo from commit A, adding a missed import for commit B, adjusting behavior introduced in a prior commit), use a fixup commit instead of a standalone commit:
   ```bash
   ~/.cursor/skills/lint-commit.sh --fixup <hash> [files...]
   ```
   This marks the commit for automatic squashing into the target commit. Use `git log --oneline` to find the target hash.
6. Include a `CHANGELOG.md` entry in the **last feature commit** (not a separate commit) using format: `- type: description`
   - Types: `added`, `changed`, `fixed`
   - Example: `- added: New short feature description`
   - Entries are grouped by type in order: all `added`, then all `changed`, then all `fixed`
   - CHANGELOG.md must ONLY appear in the last commit — never in intermediate feature commits
   - Avoid reading more than 50 lines of the file
   - **Which section** (see CHANGELOG placement rules below)
</step>

<edge-cases name="edge-react-gui only">
The following apply only when working in the `edge-react-gui` repo:

- New string literals should be added to `en_US.ts` in the SAME commit that uses them, not in a separate commit. The `lint-commit.sh` script handles `yarn localize` automatically when `en_US.ts` is in the changeset.
- **Editing `en_US.ts`**: Use grep to find exact insertion points rather than reading the file in chunks. The file is ~2500 lines; reading it piecemeal wastes context. Example:
  ```bash
  rg -n "nearby_string_key" src/locales/en_US.ts
  ```
  Then use StrReplace with minimal context — only enough surrounding lines to make the match unique. Do NOT reformat existing lines in the replacement.

### CHANGELOG placement (edge-react-gui)

`edge-react-gui` has two active CHANGELOG sections: `## Unreleased (develop)` and `## X.Y.Z (staging)`. Which section to target depends on the Asana task's version project:

1. **Read the staging version** from CHANGELOG: grep for `^## [0-9].*staging` to get the version (e.g. `4.43.0`).
2. **Read the task's version project** from the `VERSION_PROJECT` field in the Asana context output (e.g. `4.44.0`).
3. **Compare**:
   - If `VERSION_PROJECT` matches the staging version → add entry under the `## X.Y.Z (staging)` heading.
   - If `VERSION_PROJECT` does NOT match (or is not set) → add entry under `## Unreleased (develop)`.
4. If no Asana context was fetched, default to `## Unreleased`.

Other repos only have `## Unreleased` — no staging distinction.
</edge-cases>

<step id="4" name="History cleanup">
**Always run this step** — do not skip it and do not ask for permission. Review the branch history against the `clean-history` rule and automatically fix any issues found.

1. **Check for an open PR**: Run `gh pr view --json url,reviews 2>/dev/null` to determine if a PR exists and whether it has human review comments.
2. **If a PR exists with human review comments**, skip cleanup — rewriting history would lose review context. Note the pending cleanup in the retrospective.
3. **Otherwise (no PR, or PR with no human reviews)**, always perform ALL applicable cleanup automatically:
   - **Fixup commits exist**: Autosquash with `rm -f .git/index.lock && GIT_SEQUENCE_EDITOR=true git rebase -i --autosquash <base-branch>`. Do this immediately — never leave fixup commits unsquashed.
   - **Reorder commits**: Use the companion script to reorder commits to the desired order. Hashes are oldest-to-newest:
     ```bash
     ~/.cursor/skills/im/scripts/reorder-commits.sh <base-branch> <hash1> <hash2> ...
     ```
     The script handles index lock cleanup, awk-based reordering, and verifies the tree is unchanged afterward.
   - **Structural issues** (add-then-remove cycles, misplaced changes, commits that should be squashed, CHANGELOG in intermediate commits): Use `reorder-commits.sh` for reordering. For squash/drop operations, use `rm -f .git/index.lock && GIT_SEQUENCE_EDITOR="..." git rebase -i <base-branch>` with an awk or sed script. Verify the final tree matches the pre-restructure state with `git diff`.
     </step>

<step id="5" name="Verification">
Run full verification to catch issues that per-commit checks (`lint-commit.sh`) may have missed (e.g. transitive snapshot breakage, type errors across files):

```bash
~/.cursor/skills/verify-repo.sh . --base <upstream-ref>
```

Where `<upstream-ref>` is `origin/develop` for `edge-react-gui` or `origin/master` for other repos. Set `block_until_ms: 120000`.

If verification fails, fix the issue with a fixup commit targeting the responsible commit, then re-run history cleanup (step 4) and verification.
</step>

<step id="6" name="Retrospective">
When finished, evaluate the context and propose potential improvements to this process — mistakes or errors in the tool calls, ways to improve excessive context bloat, etc.
</step>
