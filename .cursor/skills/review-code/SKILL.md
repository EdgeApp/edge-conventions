---
name: review-code
description: Review code changes for quality and convention compliance. Supports both GitHub pull requests and local branches.
---

# Review Code Skill

Review code changes for quality and convention compliance. The heavy lifting (repo checkout, diff generation, subagent selection) is handled by scripts in `scripts/` adjacent to this file.

## Step 1: Prepare

Determine the absolute path to the `scripts/` directory next to this SKILL.md.

Run the prep script with the user's input (PR URL, PR number, branch name, or `"current"`):

```bash
node SCRIPTS_DIR/review-prep.js "<user-input>"
```

Parse the JSON stdout as the **manifest**. Key fields:

| Field              | Description                                             |
| ------------------ | ------------------------------------------------------- |
| `repo` / `owner`   | Repository name and GitHub owner                        |
| `branch`           | Head branch name                                        |
| `baseBranch`       | Base branch for comparison                              |
| `prNumber` / `prUrl` | PR metadata (null for local branches)                 |
| `changedFiles`     | Array of changed file paths                             |
| `diffFile`         | Path to the full unified diff on disk                   |
| `subagents`        | Map of subagent name → file list / boolean / false      |
| `existingReviews`  | Prior reviewer comments (for deduplication)             |
| `diffSummary`      | One-line stat summary                                   |

Save the manifest to `/tmp/MMDDHHmm_<repo>_<branch>_<pr-N|review>_manifest.json` (same naming convention as the final review document, but with a `_manifest.json` suffix).

## Step 2: Launch Subagents

For each entry in `manifest.subagents`:

- **Skip** if the value is `false` or an empty array `[]`.
- **Launch** if the value is `true` (no file filtering) or a non-empty array (those specific files).

Use the Task tool with the matching `subagent_type` (e.g. `review-react`, `review-async`, etc.). Launch up to 4 in parallel; batch the rest.

Each subagent prompt must include:

1. Repository: `{owner}/{repo}`, branch: `{branch}`, base: `{baseBranch}`
2. The file list from the manifest entry
3. The diff content for those files (read from `manifest.diffFile` and extract the relevant sections)
4. Prior reviewer comments from `manifest.existingReviews` so the subagent avoids duplicating feedback
5. **Output format instruction**: "Return your findings as a JSON array. Each element: `{severity, file, line, endLine, message, recommendation}` where severity is `critical`, `warning`, or `suggestion`. `line`/`endLine` are optional. If no issues found, return `[]`."

## Step 3: Generate Report

Merge all subagent findings into a single JSON array. Save to `/tmp/MMDDHHmm_<repo>_<branch>_<pr-N|review>_findings.json` (same naming convention as the manifest).

```bash
node SCRIPTS_DIR/review-report.js --manifest /tmp/<manifest-filename> --findings /tmp/<findings-filename>
```

The script outputs the path to the generated review markdown document.

## Step 4: Present

- **Cursor IDE** (if `CURSOR_TRACE_ID` env var is set): `cursor --reuse-window <review-document-path>`
- **Terminal agent**: print the full file path.

## Step 5: Submit (GitHub PRs Only)

If `manifest.prNumber` is set, submit the review to GitHub:

```bash
node SCRIPTS_DIR/review-submit.js --repo <owner>/<repo> --pr <prNumber> --review-file <review-document-path>
```

The script outputs the review URL.

For local branches: skip submission and offer to help fix issues or create a PR.
