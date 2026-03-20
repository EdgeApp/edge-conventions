---
name: pr-review
description: Review PR changes against Edge coding conventions and post structured inline feedback to GitHub. Use when the user wants to review a pull request.
compatibility: Requires git, gh.
metadata:
  author: j0ntz
---

<goal>Review PR changes against Edge coding conventions and post structured inline feedback to GitHub.</goal>

<rules description="Non-negotiable constraints.">
<rule id="standards-first">Read review standards BEFORE examining code. Load both `~/.cursor/rules/review-standards.mdc` and `~/.cursor/rules/typescript-standards.mdc` in parallel.</rule>
<rule id="use-companion-script">Use `scripts/github-pr-review.sh` for all GitHub API operations. Do not use raw `curl`, `gh`, or MCP tools inline.</rule>
<rule id="no-script-bypass">If a companion script fails, report the error and STOP. Do NOT fall back to raw `gh`, `curl`, or other workarounds.</rule>
<rule id="no-duplicate-feedback">Check existing reviews from the context output. Do not repeat feedback already given by another reviewer.</rule>
<rule id="batch-reads">When reviewing changed files, batch independent Read/Grep calls in a single message.</rule>
<rule id="script-timeouts">The companion script may take up to 30s. Set `block_until_ms: 60000` when invoking it.</rule>
</rules>

<step id="1" name="Gather PR context">
Run the companion script to fetch PR metadata, changed files with patches, and existing reviews:

```bash
scripts/github-pr-review.sh context [--pr <number>] [--owner <owner>] [--repo <repo>]
```

If the user provides a PR URL or number, pass `--pr`. If they also specify a repo, pass `--owner` and `--repo`. If nothing is provided, the script auto-detects from the current branch.

If the script exits code 2 with `PROMPT_GH_AUTH`, prompt: "`gh` CLI is not authenticated. Run `gh auth login` first."

Save the output JSON — it contains `number`, `title`, `url`, `headRef`, `baseRef`, `headSha`, `reviews[]`, and `files[]` (with patches).
</step>

<step id="2" name="Checkout PR branch">
Checkout the PR branch to ensure file reads reflect the PR's code, not the current local branch:

```bash
git fetch origin <headRef> && git checkout <headRef>
```

Replace `<headRef>` with the branch name from the context output (e.g., `william/fix-eth-sync`).

If checkout fails due to uncommitted changes, prompt the user to stash or commit before proceeding.
</step>

<step id="3" name="Load review standards">
Read these files in parallel (skip any already present in `cursor_rules_context`):

- `~/.cursor/rules/review-standards.mdc`
- `~/.cursor/rules/typescript-standards.mdc`
</step>

<step id="4" name="Review changed files">
For each changed file in the context output:

1. Read the full file to understand surrounding context (batch reads in parallel)
2. Review the patch against all loaded standards
3. Check for:
   - Convention violations from review-standards.mdc and typescript-standards.mdc
   - Potential bugs or safety issues
   - Performance concerns
   - Unnecessary code, unnecessary JSX fragments, or missed simplifications
   - Efficient memoization where necessary (memo, useHandler, useCallback)

Categorize findings as:
- **Critical**: Must fix before merge
- **Warning**: Should address
- **Suggestion**: Consider for improvement

Cross-reference findings against `reviews[]` from the context output. Omit any findings already raised by another reviewer.
</step>

<step id="5" name="Submit review">
If there are findings to report, prepare a review JSON and submit via the companion script:

```bash
echo '<review-json>' | scripts/github-pr-review.sh submit \
  --pr <number> --owner <owner> --repo <repo> --sha <headSha>
```

Review JSON format:
```json
{
  "event": "COMMENT",
  "body": "",
  "comments": [
    {
      "path": "src/file.ts",
      "line": 42,
      "side": "RIGHT",
      "body": "Comment text"
    }
  ]
}
```

Use `"REQUEST_CHANGES"` for critical issues, `"COMMENT"` for suggestions only, `"APPROVE"` if no issues found.

<sub-step name="Comment formatting">
- Single line: use only `line`
- Multi-line range: use both `start_line` (first) and `line` (last)
- `side`: use `"RIGHT"` for new code (additions)
- Keep comments concise, use backtick formatting for code, bold, or italics
- 0 findings: No review needed
- 1 inline comment: Leave `body` empty (`""`)
- 2+ inline comments: Only add `body` if it provides necessary linking context
</sub-step>
</step>

<step id="6" name="Summarize">
After submitting (or if no findings), provide a summary in the chat response:
- Number of files reviewed
- Findings by category (critical, warning, suggestion)
- Link to the submitted review
 - PR link [PR title](https://github.com/EdgeApp/<repo>/pull/5952)
</step>

<edge-cases>
<case name="No PR found">Script exits with an error. Ask the user for a PR number or URL.</case>
<case name="No changed files">Report that the PR has no file changes.</case>
<case name="Large PR (>20 files)">Prioritize files with the most additions. Note any files skipped due to size.</case>
<case name="Server repo">If the repository name ends in `-server` or context indicates a server project, also review against the Server Conventions section in review-standards.mdc.</case>
</edge-cases>
