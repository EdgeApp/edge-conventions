---
name: review-code
description: Review code changes for quality and convention compliance. Supports GitHub pull requests, local branches, commit ranges, and uncommitted changes.
---

# Review Code Skill

Review code changes for quality and convention compliance. The heavy lifting (resolving the change, diff generation, subagent selection) is handled by scripts in `scripts/` adjacent to this file.

Use the `deploy` branch of edge-conventions: it carries the current agents, skills, and scripts. Fast-forward it (`git pull --ff-only origin deploy`) before a review.

## Step 1: Prepare

Determine the absolute path to the `scripts/` directory next to this SKILL.md.

Run the prep script from the repository under review with the user's input:

```bash
node SCRIPTS_DIR/review-prep.js [--base <ref>] [--repo-dir <path>] "<user-input>"
```

| Input | Reviews |
| --- | --- |
| PR URL, or PR number (`123`, `#123`) | The PR head (fetched as `refs/pull/N/head`, forks included) against `origin/<PR base>` |
| `A..B` | Exactly the commits from `A` to `B` |
| `A...B` | From `merge-base(A, B)` to `B` |
| Branch name | That branch against its base |
| `current` | `HEAD` against its base; the uncommitted changes when nothing is committed on top of the base |

The base is `--base` when given (a bare name like `develop` means `origin/develop`), otherwise whichever of `origin/master` and `origin/develop` the head forked from. A range names its own base and ignores `--base`.

The script never checks out, switches, or resets anything: diffs come from refs, so it is safe in a checkout with work in progress. Subagents read whole files at the reviewed commit with `git -C <repoDir> show <headSha>:<path>`, not from the working tree (except in uncommitted mode).

Parse the JSON stdout as the **manifest**. Key fields:

| Field              | Description                                             |
| ------------------ | ------------------------------------------------------- |
| `repo` / `owner`   | Repository name and GitHub owner (from the `origin` remote) |
| `mode`             | `pr`, `range`, `branch`, or `current`                   |
| `branch`           | Head branch name (null for a range no branch points at) |
| `baseBranch`       | Base ref the diff is taken against                      |
| `mergeBase` / `headSha` | The diff runs from `mergeBase` to `headSha`        |
| `range`            | The range as given (range mode)                         |
| `uncommitted`      | True when the diff is the working tree                  |
| `prNumber` / `prUrl` | PR metadata (null otherwise)                          |
| `repoDir`          | The checkout the refs were read from                    |
| `changedFiles`     | Array of changed file paths                             |
| `diffFile`         | Path to the full unified diff on disk                   |
| `subagents`        | Map of subagent name → file list / boolean / false      |
| `existingReviews`  | Prior reviewer comments (for deduplication)             |
| `diffSummary`      | One-line stat summary                                   |

Every file in `.cursor/agents/` appears in `subagents`. An agent the script has no selection rule for gets every changed file.

Save the manifest to `/tmp/MMDDHHmm_<repo>_<branch>_<pr-N|review>_manifest.json` (same naming convention as the final review document, but with a `_manifest.json` suffix).

## Step 2: Launch Subagents

For each entry in `manifest.subagents`:

- **Skip** if the value is `false` or an empty array `[]`.
- **Launch** if the value is `true` (no file filtering) or a non-empty array (those specific files).

Use the Task tool with the matching `subagent_type` (e.g. `review-react`, `review-async`, `review-performance`, etc.). Launch up to 4 in parallel; batch the rest.

Each subagent prompt must include:

1. Repository: `{owner}/{repo}`, branch: `{branch}`, base: `{baseBranch}`, reviewed commits `{mergeBase}..{headSha}`, checkout `{repoDir}`
2. The file list from the manifest entry
3. The diff content for those files (read from `manifest.diffFile` and extract the relevant sections)
4. Prior reviewer comments from `manifest.existingReviews` so the subagent avoids duplicating feedback
5. **Output format instruction**: "Return your findings as a JSON array. Each element: `{severity, file, line, endLine, message, recommendation}` where severity is `critical`, `warning`, or `suggestion`. `line`/`endLine` are optional. If no issues found, return `[]`."

## Step 3: Generate Report

Merge all subagent findings into a single JSON array. Save to `/tmp/MMDDHHmm_<repo>_<branch>_<pr-N|review>_findings.json` (same naming convention as the manifest).

```bash
node SCRIPTS_DIR/review-report.js --manifest /tmp/<manifest-filename> --findings /tmp/<findings-filename>
```

The script outputs the path to the generated review markdown document. Severities other than the three above (`0`–`3`, `high`, `nit`, …) are mapped onto them; anything unrecognised is listed under "Other", never dropped.

## Step 4: Present

- **Cursor IDE** (if `CURSOR_TRACE_ID` env var is set): `cursor --reuse-window <review-document-path>`
- **Terminal agent**: print the full file path.

## Step 5: Submit (GitHub PRs Only)

If `manifest.prNumber` is set, submit the review to GitHub:

```bash
node SCRIPTS_DIR/review-submit.js --repo <owner>/<repo> --pr <prNumber> --review-file <review-document-path>
```

The script outputs the review URL. It requests changes for a critical finding, comments for a warning, and approves otherwise; on your own PR GitHub allows only a comment, so it comments. `--event APPROVE|COMMENT|REQUEST_CHANGES` overrides.

For local branches and ranges: skip submission and offer to help fix issues or create a PR.

## Tests

```bash
node --test .cursor/skills/review-code/scripts/test/*.test.js
```
