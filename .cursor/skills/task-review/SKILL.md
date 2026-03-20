---
name: task-review
description: Fetch context from an Asana task, analyze it, present a summary, and determine the target repo. Use when the user provides an Asana task link for review.
compatibility: Requires jq. ASANA_TOKEN for Asana integration.
metadata:
  author: j0ntz
---

<goal>Fetch context from an Asana task, analyze it, present a summary, and determine the target repo. This is the **single source of truth** for Asana task understanding — both `im.md` and `pr-create.md` delegate here.</goal>

<rules description="Non-negotiable constraints.">
<rule id="summary-first">Present the task summary to the user BEFORE exploring any code. Code exploration happens after the user has seen the analysis.</rule>
<rule id="script-timeout">The `asana-get-context.sh` script can take up to 90s (PDF conversion is slow). Always set `block_until_ms: 120000` when invoking it.</rule>
</rules>

<when-this-runs>
- Automatically as the first step of `im.md` when an Asana task link is provided
- Automatically as Step 1 of `pr-create.md` when an Asana task link is provided
- Can also be invoked standalone: `/task-review https://app.asana.com/1/.../task/<task_gid>`
</when-this-runs>

<step id="1" name="Fetch task context and attachments">
Extract the `task_gid` (the final numeric ID in the URL) and run:

```bash
~/.cursor/skills/asana-get-context.sh <task_gid>
```

This fetches task metadata, comments, and **automatically downloads and processes attachments** to `/tmp/asana-task-<task_gid>/`:

- **Text files** (`.md`, `.txt`, `.json`, `.csv`, `.log`, `.yaml`, `.yml`): Downloaded directly — read them.
- **PDFs**: Text-extracted first (`PDF_TEXT:` output). If the PDF is image-based, converted to page images (`PDF_PAGES:` output).
- **ZIPs**: Unpacked recursively (`UNPACKED:` output). Extracted files (including PDFs inside) are then processed by the same handlers.
- **Images** (`.png`, `.jpg`, `.gif`, `.webp`): Downloaded directly — read them.

<sub-step name="Reading processed attachments">
After the script completes, read the processed files based on the output:

1. **`DOWNLOADED:` paths** — Read any `.txt`, `.md`, `.json`, `.csv`, `.yaml`, `.yml` files listed.
2. **`PDF_TEXT:` paths** — Read the extracted `.txt` file. This is the full text content of the PDF.
3. **`PDF_PAGES:` directories** — Read the page images (`page-01.png`, `page-02.png`, etc.) using the Read tool. For large documents (>20 pages), read the first 10 pages, then skim the rest by reading every 3rd-5th page.
4. **`UNPACKED:` directories** — List contents (`ls -R`), then read relevant files (text files, images, etc.). Skip macOS metadata (`__MACOSX/`, `.DS_Store`).
</sub-step>

<sub-step name="No attachments case">
If `ATTACHMENTS: (none)` appears in script output, do **not** probe `/tmp/asana-task-<task_gid>/`. Treat missing `/tmp` paths as expected in this case and continue to Step 2.
</sub-step>
</step>

<step id="2" name="Determine target repo">
**Task title prefixes are deterministic signals:**

| Prefix | Repository | Branch from |
|--------|------|-------------|
| `gui:` | `edge-react-gui` | `develop` |
| `exch:` | `edge-exchange-plugins` | `master` |
| `accb:` | `edge-currency-accountbased` | `master` |
| `core:` | `edge-core-js` | `master` |

**Always create feature branches from the "Branch from" column.** `edge-react-gui` uses `develop` as its integration branch; the others use `master`.

If no prefix is present, infer from the task description, keywords, or attached PRs. If still unclear, ask the user.
</step>

<step id="3" name="Summarize understanding">
Present a concise summary to the user covering:

1. **What**: One-sentence description of the task/bug in your own words (not just parroting the title)
2. **Why**: The motivation — what problem does this solve or what value does it add?
3. **Target repo**: Which repo (determined in Step 2)
4. **Scope**: What files/areas of the codebase are likely involved? Use the task description, comments, and your knowledge of the repo to estimate.
5. **Approach**: A brief proposed approach (1-3 bullets). If multiple approaches exist, list them with tradeoffs.
6. **Priority**: Note the priority level if set.

<sub-step name="Surfacing questions">
After the summary, list any:
- **Ambiguities**: Requirements that are unclear or could be interpreted multiple ways
- **Missing info**: Information needed that isn't in the task
- **Contradictions**: Conflicting statements between the description and comments
- **Decisions needed**: Choices that the user should weigh in on before implementation begins

If there are no questions, say so explicitly — don't fabricate them.
</sub-step>

<sub-step name="Using comments and attachments">
- **Comments**: Read for updated requirements, decisions, or clarifications that may override the original description. Call out any that change scope.
- **Text attachments**: Read downloaded text files for additional context (specs, requirements, analysis). Reference relevant content in the summary.
- **PDF attachments**: Summarize key content from extracted text or page images. For brand guidelines, note colors, logos, naming, and other visual details.
- **ZIP attachments**: Note the contents and any relevant files found inside. For asset packages (logos, icons), describe the available formats and variants.
- **Image attachments**: View and describe the content. Note any UI mockups, designs, or reference screenshots.
</sub-step>
</step>

<step id="4" name="Wait for confirmation (im.md and standalone only)">
When invoked from `im.md` or standalone, end with a clear prompt:

> Does this match your understanding? Any adjustments before I start?

**Do NOT begin implementation until the user confirms.**

When invoked from `pr-create.md`, skip this step — the task context is used for repo/branch resolution and PR enrichment, not for implementation planning.
</step>
