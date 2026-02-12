---
name: author
description: Create, edit, revise, or debug Cursor commands (~/.cursor/commands/*.md) and skills (~/.cursor/skills/*/SKILL.md). Use when the user wants to make a new slash command, update an existing command, write a skill, fix a skill, or asks about .cursor/commands/ or .cursor/skills/ files. Also use when the user says "new command", "create command", "create skill", "edit command", "new skill", "update skill", "update command",or references SKILL.md. NOT for general markdown editing (READMEs, CHANGELOGs, docs, AGENTS.md).
---

<goal>Write or revise Cursor commands and skills with maximum agent compliance.</goal>

<commands-vs-skills>
Commands (`~/.cursor/commands/*.md`): Invoked explicitly via `/command-name`. Deterministic — always fires when the user types the slash command. Can have `.sh` companion scripts.

Skills (`~/.cursor/skills/*/SKILL.md`): Agent-triggered based on task matching against the description. Heuristic — not guaranteed to fire.

Use a command when the user wants an explicit trigger. Use a skill when the behavior should activate automatically based on context.
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

<revision-checklist>
When revising an existing command, **every item below is mandatory** — not a suggestion. Older commands may predate current best practices; touching a command is an opportunity to bring it up to spec.

1. Read the full file before making changes
2. Check for duplicated logic across other commands — consolidate if found
3. Verify step ordering matches the agent's decision flow
4. Ensure examples are brief and generic (no real repo names, PR numbers, or user data)
5. Check that escape hatches exist for ambiguous cases
6. Confirm companion scripts match the `.md` expectations
7. Convert markdown-structured commands to XML format (this is the most commonly skipped item — `##` headers and bullet lists must become `<goal>`, `<rules>`, `<step>` tags)
8. Apply all current authoring principles (rules-first, scripts-over-reasoning, batch-tool-calls, etc.) even if the original command predates them
</revision-checklist>

<companion-scripts>
Scripts go in `~/.cursor/commands/` alongside the `.md` file. Conventions:

- `set -euo pipefail` at the top
- Parse args with a `while/case` loop
- Output structured, one-line-per-action summaries the agent can parse
- Exit code 0 = success, 1 = error, 2 = needs user input
- **Naming**: Name scripts by what they DO, not which command they serve. Scripts will likely be reused by multiple commands. Prefer descriptive, domain-scoped names over command-coupled names:
  - `lint-commit.sh` — good (describes the operation)
  - `asana-attach-pr.sh` — good (describes the operation)
  - `github-pr-comments.sh` — good (describes the domain + operation)
  - `pr-address.sh` — bad (coupled to the `/pr-address` command name)
- Before creating a new script, check if an existing script already covers the operation. Extend it with a new subcommand rather than creating a duplicate.
- **GitHub API**: Default to `gh api` and `gh api graphql` — never raw `curl`. See `gh-cli-over-curl` principle.
</companion-scripts>
