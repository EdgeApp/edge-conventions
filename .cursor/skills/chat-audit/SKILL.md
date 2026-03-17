---
name: chat-audit
description: Analyze a Cursor chat export to identify inefficiencies, rule violations, and wasted tool calls. Use when the user wants to audit a chat session.
compatibility: Requires node.
metadata:
  author: j0ntz
---

<goal>Analyze current chat or provided Cursor chat export to identify inefficiencies, rule violations, and wasted tool calls against the invoked command's workflow.</goal>

<rules description="Non-negotiable constraints.">
<rule id="use-companion-script">Use `scripts/cursor-chat-extract.js` to parse the export. Do NOT parse the raw JSON inline — it is deeply nested and will consume excessive context.</rule>
<rule id="tools-only-default">Default to `--tools-only` mode. Only omit the flag if the user asks for full assistant message analysis.</rule>
<rule id="no-raw-json">Do NOT read the export JSON file directly. All data comes from the script output.</rule>
<rule id="concise-output">Keep the final report under 50 lines. Use a numbered list for findings, not verbose paragraphs.</rule>
</rules>

<step id="1" name="Extract conversation data">
If no chat export file is provided, assume the user is asking for a chat audit of the current chat session.

If chat export file is provided, run the companion script on the user-provided export file:

```bash
scripts/cursor-chat-extract.js <export-file> --tools-only
```

Parse the JSON output. Note the `invokedCommand`, `stats`, and `sequence` fields.

If `invokedCommand` is null, check the first user message for a command reference and ask the user which command was intended.
</step>

<step id="2" name="Load the invoked command">
If `invokedCommand` is identified, read the command file:

```bash
Read ~/.cursor/skills/<invokedCommand>/SKILL.md
```

Extract the command's:
- **Rules** (the `<rule>` tags)
- **Steps** (the `<step>` tags — just names and key instructions, not full content)
- **Companion scripts** referenced (filenames only)
</step>

<step id="3" name="Analyze tool call sequence">
Walk through the `sequence` array and check each tool call against the command's prescribed workflow:

<sub-step name="Rule violations">
For each rule in the command, check if the tool sequence violates it:
- `commit-script`: Did the agent use raw `git add` + `git commit` instead of `lint-commit.sh`?
- `use-companion-script`: Did the agent call `gh`, `curl`, or API tools directly instead of the prescribed script?
- `no-script-bypass`: Did the agent fall back to raw tools after a script error?
- Cross-reference rules: Did the agent read files referenced with "Read ... now (do NOT skip)"?
</sub-step>

<sub-step name="Wasted tool calls">
Flag calls that consumed context without contributing to the workflow:
- **Errors followed by retries** — the error was avoidable (e.g., reading a directory as a file)
- **Redundant reads** — same information gathered multiple times (e.g., `git status` called twice)
- **Unnecessary exploration** — reading code files when the user said the change was already done
- **Sleep-based polling** — `sleep N && tail` instead of using `block_until_ms`
- **Sequential calls that could be parallel** — independent operations run one at a time
</sub-step>

<sub-step name="Skipped steps">
For each step in the command, check if the tool sequence includes the corresponding action:
- Missing verification step
- Missing CHANGELOG entry
- Missing Asana linking
- Skipped cross-file reads (e.g., never read `im.md` when step 3 requires it)
</sub-step>
</step>

<step id="4" name="Generate report">
Output a structured report:

```
## Chat Audit: /<command>

**Stats:** N tool calls (M errors, K cancelled) across L user messages

### Rule Violations
1. [rule-id] Description of what happened

### Wasted Tool Calls
1. [#N] tool_name — why it was wasteful

### Skipped Steps
1. [step N] What was skipped

### Recommendations
1. Specific change to the command file that would prevent this
```

If the user hasn't asked for command file changes, stop here. If they ask, apply the recommendations using the `/author` skill.
</step>

<edge-cases>
<case name="No command detected">Ask the user which command was being executed, or analyze without a reference command (just flag errors and wasted calls).</case>
<case name="Multiple user messages">The conversation may span multiple turns. The first user message typically invokes the command; subsequent ones are follow-ups. Analyze the full sequence but weight findings toward the initial command execution.</case>
<case name="Non-command conversation">If no `/command` was invoked, still analyze for general inefficiencies (redundant reads, errors, unnecessary exploration) but skip the rule/step compliance checks.</case>
</edge-cases>
