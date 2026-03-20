---
name: author
description: Create, edit, revise, or debug Cursor skills (~/.cursor/skills/*/SKILL.md). Use when the user wants to make a new skill, update an existing skill, fix a skill, or asks about .cursor/skills/ files. Also use when the user says "new command", "create command", "create skill", "edit command", "new skill", "update skill", "update command", or references SKILL.md. NOT for general markdown editing (READMEs, CHANGELOGs, docs, AGENTS.md).
---

<goal>Write or revise Cursor commands and skills with maximum agent compliance.</goal>

<commands-vs-skills>
Skills (`~/.cursor/skills/*/SKILL.md`): The standard unit. Can be invoked explicitly via `/skill-name` or agent-triggered based on task matching against the description. Companion scripts live in `<skill>/scripts/`. Shared scripts live at `~/.cursor/skills/` top-level.
</commands-vs-skills>

<authoring-principles>
<principle id="prescriptive">Be prescriptive, not descriptive. Commands tell the agent what to DO, not what things ARE.</principle>
<principle id="brief-examples">Examples must be brief and hypothetical. Never use real data from conversations. Keep examples to 3-5 lines max.</principle>
<principle id="dry">DRY across commands. If two commands share logic, extract it into a shared file and have both reference it.</principle>
<principle id="ordering">Order of operations matters. The agent reads top-to-bottom. Put context-setting steps before action steps.</principle>
<principle id="rules-first">Hard rules at the top. Non-negotiable constraints go right after the Goal so they're read before any steps.</principle>
<principle id="escape-hatches">Escape hatches over assumptions. When ambiguity exists, tell the agent to ask — don't let it guess.</principle>
<principle id="scripts-over-reasoning">Offload all deterministic logic to companion scripts. If an operation has a known, repeatable sequence of steps (API calls, git commands, file parsing, linting, data fetching), it belongs in a `.sh` script — not inline in the `.md` as shell blocks the agent must reason about. The `.md` file should only handle semantic decisions, user interaction, and interpreting script output. This eliminates context bloat and prevents the agent from re-deriving logic it doesn't need to understand.</principle>
<principle id="batch-tool-calls">Minimize round-trips. When a step requires multiple independent pieces of information (e.g., git status + git log + git diff), instruct the agent to gather them all in parallel tool calls within a single message/script — not sequentially. Group independent reads, searches, and shell commands together. Only sequence calls when one depends on the output of another.</principle>
<principle id="no-duplicate-automation">Don't duplicate in semantic rules what companion scripts already automate. If a script handles linting, formatting, localization, or other post-processing, the command should reference the script — not also instruct the agent to perform those steps. Duplication risks the agent running a step twice or conflicting with the script's output.</principle>
<principle id="gh-cli-over-curl">For GitHub API operations in companion scripts, use `gh api` and `gh api graphql` over raw `curl` + `$GITHUB_TOKEN`. `gh` handles authentication, pagination (`--paginate`), and API versioning automatically. Use GraphQL (`gh api graphql -f query="..."`) to fetch only required fields in a single request, reducing API calls and context size. Fall back to REST (`gh api repos/...`) only when GraphQL doesn't expose the needed data (e.g., file patches).</principle>
<principle id="node-over-python">When companion scripts need capabilities beyond bash (JSON manipulation, complex regex, structured data processing, async I/O), embed Node.js inline via `exec node -e '...'` rather than depending on Python. Node is already a required dependency for other scripts; adding Python creates an unnecessary second runtime dependency. This keeps scripts as single `.sh` files while unlocking full-featured processing. Avoid single quotes inside the inline node code (bash single-quoted string boundary); use `\x27` in regex to match literal single quotes.</principle>
<principle id="minimize-context">Companion scripts must minimize context consumption. Return structured, filtered summaries — never raw API responses or full file contents. When a script processes large inputs (logs, exports, API payloads), extract only the fields the command needs and discard the rest. Commands should instruct the agent to use targeted reads (grep, line ranges) over full file reads for large files. Every token of script output that the agent reads costs context — design outputs to be as compact as possible while remaining parseable.</principle>
</authoring-principles>

<formatting>
Use XML tags to structure commands and skills. XML outperforms markdown for LLM instruction-following:

- Anthropic, OpenAI, and Google all recommend XML tags for structuring prompts.
- Claude is specifically tuned to attend to XML tag boundaries.
- Empirical tests show up to 40% performance variance based on prompt format alone, with XML consistently outperforming markdown.

Source: https://docs.claude.com/en/docs/use-xml-tags

<rules>
- Use semantic tag names that describe their content (e.g., `<rules>`, `<step>`, `<edge-cases>`).
- Use attributes for metadata: `id`, `name`, `description`.
- Nest tags for hierarchy: `<step><sub-step>...</sub-step></step>`.
- Be consistent — use the same tag names throughout a command.
- Markdown is still fine for inline formatting within XML tags (bold, code, lists).
</rules>

<template>
```xml
<goal>One sentence. What does this command accomplish?</goal>

<rules description="Non-negotiable constraints.">
<rule id="constraint-1">...</rule>
<rule id="constraint-2">...</rule>
</rules>

<step id="1" name="Step name">
Instructions for this step.
</step>

<step id="2" name="Step name">
Instructions for this step.
</step>

<edge-cases>
<case name="Case name">How to handle it.</case>
</edge-cases>
```
</template>
</formatting>

<small-model-conventions description="Apply these when the command will run on smaller/faster models (e.g., the user says 'for smaller models', 'optimize for lite/fast', or the command is high-frequency and must be cheap). These patterns compensate for weaker instruction-following and shorter reasoning chains.">

<convention id="verbatim-bash">Give exact shell commands to copy-paste, not descriptions of what to run. Smaller models copy verbatim; they struggle to construct commands from prose. Include placeholders like `<upstream-ref>` only where the agent must substitute a value.</convention>

<convention id="file-over-args">Pass multi-line content (PR bodies, commit messages, JSON payloads) via temp files, not shell arguments. Write content using the Write tool, then pass `--body-file /tmp/foo.md` to the script. This avoids shell escaping failures that smaller models cannot debug.</convention>

<convention id="exact-output-templates">When the command produces formatted output (markdown, JSON, reports), show the exact template line-by-line with placeholders. Include blank lines and heading levels explicitly. Example: show `## Accomplishments {day_label}` not "add a heading for accomplishments."</convention>

<convention id="explicit-parallel">Spell out parallel tool calls: "Run both scripts **in parallel** (two Shell tool calls in one message)." Smaller models default to sequential unless explicitly told otherwise.</convention>

<convention id="priority-ordered-decisions">When the agent must categorize or choose between options, use a numbered priority list — not prose. Example: "1. If X → do A. 2. If Y → do B. 3. Otherwise → do C." Smaller models follow numbered sequences reliably; they lose track of nested if/else prose.</convention>

<convention id="inline-guardrails">Duplicate critical rules from cross-referenced files as top-level `<rule>` tags. Smaller models skip "Read file X now" instructions despite explicit language. One-liner guardrails (e.g., `commit-script`, `changelog-required`) catch the failure mode where the cross-read is skipped entirely.</convention>

<convention id="no-implicit-steps">Every action needs an explicit instruction. Never rely on "follow best practices" or "use appropriate patterns." If the agent should run `git push -u origin HEAD`, write that exact command — don't say "push the branch."</convention>

<convention id="single-tool-per-step">Where possible, design steps so each step is ONE tool call. Smaller models lose track of multi-tool steps. If a step requires multiple calls, break it into sub-steps with explicit sequencing ("After step 2a completes, run step 2b").</convention>
</small-model-conventions>

<revision-checklist>
When revising an existing command, **every item below is mandatory** — not a suggestion. Older commands may predate current best practices; touching a command is an opportunity to bring it up to spec.

1. Read the full file before making changes
2. Check for duplicated logic across other commands — consolidate if found
3. **Check behavioral dependencies**: Search for other commands, skills, and rules that perform similar operations or share domain overlap with the one being edited. If command A has a step that is a lightweight version of command B's core behavior (e.g., `/pr-land` addressing comments vs `/pr-address`), verify that A's step is consistent with B's rules — missing rules in A are likely bugs.
   - Extract domain-specific verbs and nouns from the step being edited (e.g., a step about handling PR comments yields: `comment`, `reply`, `resolve`, `address`, `fixup`, `thread`)
   - Search each term across commands, skills, and rules:
   ```bash
   rg -l "<term>" ~/.cursor/skills/*/SKILL.md ~/.cursor/rules/*.mdc
   ```
   - Read any hits that share domain overlap and check for consistency
   - If overlap is found, evaluate whether to consolidate per the `dry` principle: can A reference B's rules or a shared file instead of reimplementing? Propose consolidation to the user when the shared logic is non-trivial.
4. **Check dependent callers before any script/command change**: Before adding, updating, renaming, or removing any command, skill, script, step ID, flag, or output contract, search for direct callers/references and update them in the same change.
   - Search by skill name, script filename, flag names, and any removed/renamed identifiers:
   ```bash
   rg -n "<identifier>" ~/.cursor/skills ~/.cursor/rules
   ```
   - Do not add/update/remove script behavior until caller impacts are audited and required updates are planned.
   - Do not delete or rename a referenced target until all callers are updated.
   - In the final response, list which callers were updated.
5. Verify step ordering matches the agent's decision flow
6. Ensure examples are brief and generic (no real repo names, PR numbers, or user data)
7. Check that escape hatches exist for ambiguous cases
8. Confirm companion scripts match the `.md` expectations
9. Convert markdown-structured commands to XML format (this is the most commonly skipped item — `##` headers and bullet lists must become `<goal>`, `<rules>`, `<step>` tags)
10. Apply all current authoring principles (rules-first, scripts-over-reasoning, batch-tool-calls, etc.) even if the original command predates them
11. If the command may run on smaller/faster models, apply `<small-model-conventions>` — especially `file-over-args`, `inline-guardrails`, and `verbatim-bash`
</revision-checklist>

<post-authoring-actions>
After any authoring change (skills/scripts/rules), ask:

> Run `/convention-sync` to sync files and update PR conventions/description?

When `.cursor/rules/*.mdc` files changed, run:

```bash
~/.cursor/skills/convention-sync/scripts/generate-claude-md.sh
```

This keeps `~/.claude/CLAUDE.md` aligned with always-apply rules via the existing convention-sync flow.
</post-authoring-actions>

<companion-scripts>
Skill-specific scripts go in `<skill>/scripts/`. Shared scripts go in `~/.cursor/skills/` top-level. Conventions:

- `set -euo pipefail` at the top
- Parse args with a `while/case` loop
- Output structured, one-line-per-action summaries the agent can parse
- Exit code 0 = success, 1 = error, 2 = needs user input
- **Naming**: Name scripts by what they DO, not which command they serve. Scripts will likely be reused by multiple commands. Prefer descriptive, domain-scoped names over command-coupled names:
  - `lint-commit.sh` — good (describes the operation)
  - `asana-task-update.sh` — good (describes the operation)
  - `github-pr-comments.sh` — good (describes the domain + operation)
  - `pr-address.sh` — bad (coupled to the `/pr-address` command name)
- Before creating a new script, check if an existing script already covers the operation. Extend it with a new subcommand rather than creating a duplicate.
- **GitHub API**: Default to `gh api` and `gh api graphql` — never raw `curl`. See `gh-cli-over-curl` principle.
</companion-scripts>
