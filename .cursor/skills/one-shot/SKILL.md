---
name: one-shot
description: End-to-end flow for a task: plan/context, implementation, PR creation, and Asana attach/assign in one command.
compatibility: Requires git, gh, node, jq. ASANA_TOKEN for Asana integration. ASANA_GITHUB_SECRET for PR attachment.
metadata:
  author: j0ntz
---

<goal>Run the full legacy-style task-to-PR workflow in one command by orchestrating `/asana-plan`, `/im`, and `/pr-create`.</goal>

<rules description="Non-negotiable constraints.">
<rule id="orchestrate-existing-skills">Do not re-implement logic already defined in `/asana-plan`, `/im`, or `/pr-create`. Delegate to those skills.</rule>
<rule id="attach-and-assign-default">By default, invoke `/pr-create` with both `--asana-attach` and `--asana-assign`.</rule>
<rule id="hands-off-assignment">This workflow is hands-off. If reviewer assignment cannot be resolved from task state or explicit input, let `/pr-create` skip assignment rather than pausing for reviewer input.</rule>
<rule id="task-gid-required-for-asana-flags">If Asana attach/assign flags are active, a task GID must be available from the Asana URL input or explicit `--asana-task` flag; otherwise fail fast.</rule>
<rule id="no-script-bypass">If any delegated skill or companion script fails, report and stop. Do not bypass with manual alternatives.</rule>
<rule id="pr-body-owned-by-pr-create">Do not draft alternate PR markdown formats inside this workflow. `/pr-create` owns PR body generation and template compliance.</rule>
</rules>

<step id="1" name="Collect input">
Accept one of:

1. Asana task URL
2. Text/file requirements

Optional flags:

- `--asana-task <gid>` (explicit Asana GID override)
- `--no-asana-attach`
- `--no-asana-assign`
</step>

<step id="2" name="Plan/context phase">
Run `/asana-plan` with the provided input mode:

- Asana URL mode: fetch task context and create plan
- Text/file mode: create plan from provided requirements

Wait for user confirmation handled by `/asana-plan`.
</step>

<step id="3" name="Implementation phase">
Run `/im` using the approved `/asana-plan` output.
</step>

<step id="4" name="PR phase">
Run `/pr-create` with defaults:

- include `--asana-attach` unless `--no-asana-attach`
- include `--asana-assign` unless `--no-asana-assign`

Task GID source priority:

1. explicit `--asana-task <gid>`
2. Asana task URL from step 1
3. chat context from prior steps
</step>

<step id="5" name="Report">
Return the final PR URL and which delegated phases ran:

- planning: `/asana-plan`
- implementation: `/im`
- PR creation: `/pr-create`
</step>

<edge-cases>
<case name="No Asana input with attach/assign enabled">Fail fast and ask for `--asana-task <gid>` or disable flags with `--no-asana-attach` / `--no-asana-assign`.</case>
<case name="Ad-hoc text task">Allow workflow with `--no-asana-attach --no-asana-assign` when no task link/GID exists.</case>
</edge-cases>
