<goal>Implement an Asana task or ad-hoc feature/fix with clean, well-structured commits.</goal>

<rules description="Non-negotiable constraints.">
<rule id="read-coding-standards">Before writing ANY code, read `.cursor/rules/typescript-standards.mdc` and follow all rules and standards in it throughout the implementation.</rule>
<rule id="no-impl-before-confirm">When an Asana task is provided, do NOT begin implementation until the user confirms the task summary (Step 0).</rule>
<rule id="lint-before-change">Before the first edit to ANY file, run `npx eslint <file>` (without `--quiet` — warnings must be visible). If warnings or errors exist, fix them in a separate commit IMMEDIATELY BEFORE the commit with actual changes. This applies to every file you touch, including ones discovered mid-implementation — not just the files you planned upfront.</rule>
<rule id="no-manual-formatting">Do not manually fix formatting. `lint-commit.sh` runs `eslint --fix` (which includes Prettier) before committing. If you see a formatting lint after editing, do NOT make another edit to fix it.</rule>
<rule id="commit-script">Always commit using `~/.cursor/commands/lint-commit.sh -m "message" [files...]` or `--fixup <hash>` for fixup commits.</rule>
<rule id="clean-history">The final commit history must read as a clean, straight-line progression — as if every decision was made correctly up front. Never preserve the "squiggly path" of development (adding then removing code, temporary scaffolding, exploratory commits). If you introduce something in commit A and remove it in commit B, restructure so the final history never contains it. Plan commits proactively to avoid this; when it happens anyway, restructure the branch before finishing.</rule>
<rule id="no-script-bypass">If a companion script fails, report the error and STOP. Do NOT fall back to raw `gh`, `curl`, or other workarounds.</rule>
<rule id="script-timeouts">`asana-get-context.sh` can take up to 90s. Always set `block_until_ms: 120000` when invoking it to avoid unnecessary backgrounding and polling.</rule>
</rules>

<step id="0" name="Task review (if Asana link provided)">
If an Asana task link is provided, **read `~/.cursor/commands/task-review.md` now** (use the Read tool — do NOT skip this) and follow all 4 steps including confirmation. It fetches task context, downloads and processes attachments (text files, PDFs, ZIPs, images), determines the target repo, presents a summary, surfaces questions, and **waits for user confirmation before any implementation begins**.

If no Asana link is provided, skip this step.

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

If the task spans multiple repos, note the additional repos but implement in the primary repo first.
</step>

<step id="2" name="Pre-change lint check">
**Before writing ANY code**, lint every file you currently plan to modify:

```bash
npx eslint <file1> <file2> ...
```

Do NOT use `--quiet` — warnings must be visible. If warnings or errors exist, fix ONLY those lint issues and commit them:

```bash
~/.cursor/commands/lint-commit.sh -m "Fix lint warnings in <ComponentName>" <file1> <file2> ...
```

`lint-commit.sh` automatically removes graduated files from `eslint.config.mjs` warning overrides at commit time.

This ensures the subsequent feature commit introduces zero pre-existing warnings. This is the initial pass — if you discover additional files to modify during Step 3, the same check applies (see Step 3).
</step>

<step id="3" name="Implementation">
1. **Lint-check newly discovered files**: If you need to modify a file not covered in Step 2, run `npx eslint <file>` before editing it. If pre-existing warnings exist, fix them and commit as a `--fixup` to the lint-fix commit from Step 2 (use `git log --oneline` to find the hash). If no lint-fix commit exists yet, create one.
2. Break up the feature into multiple commits if necessary. Commit messages should be a concise title without tags like "feat" and a short body.
3. Open relevant ts/tsx files before writing code.
4. Commit using `lint-commit.sh`:
   ```bash
   ~/.cursor/commands/lint-commit.sh -m "commit message" [files...]
   ```
   You can optionally pass specific files to scope the commit.
5. **Fixup commits**: When a change logically amends an earlier commit on the branch (e.g. fixing a typo from commit A, adding a missed import for commit B, adjusting behavior introduced in a prior commit), use a fixup commit instead of a standalone commit:
   ```bash
   ~/.cursor/commands/lint-commit.sh --fixup <hash> [files...]
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
   - **Fixup commits exist**: Autosquash with `GIT_SEQUENCE_EDITOR=true git rebase -i --autosquash <base-branch>`. Do this immediately — never leave fixup commits unsquashed.
   - **Structural issues** (add-then-remove cycles, misplaced changes, commits that should be squashed, CHANGELOG in intermediate commits): Use scripted `GIT_SEQUENCE_EDITOR` to drop, reorder, or squash commits, resolving conflicts as needed. Verify the final tree matches the pre-restructure state with `git diff`.
   - **Git lock conflicts**: VSCode's built-in git integration may race with rebase operations, creating `.git/index.lock` files. Always run `rm -f .git/index.lock` before any `git rebase` command to prevent stalls. If a rebase step fails with "index.lock: File exists", remove the lock and `git rebase --continue`.
</step>

<step id="5" name="Verification">
Run full verification to catch issues that per-commit checks (`lint-commit.sh`) may have missed (e.g. transitive snapshot breakage, type errors across files):

```bash
~/.cursor/commands/verify-repo.sh . --base <upstream-ref>
```

Where `<upstream-ref>` is `origin/develop` for `edge-react-gui` or `origin/master` for other repos. Set `block_until_ms: 120000`.

If verification fails, fix the issue with a fixup commit targeting the responsible commit, then re-run history cleanup (step 4) and verification.
</step>

<step id="6" name="Retrospective">
When finished, evaluate the context and propose potential improvements to this process — mistakes or errors in the tool calls, ways to improve excessive context bloat, etc.
</step>
