---
name: asana-task-update
description: Update Asana tasks via one reusable workflow (attach PRs, assign/unassign, set status, and update task fields). Use when any skill needs to modify Asana task state.
compatibility: Requires jq. ASANA_TOKEN for Asana API updates. ASANA_GITHUB_SECRET for PR attach operations.
metadata:
  author: j0ntz
---

<goal>Perform Asana task mutations through one shared command and one shared script, so all callers use the same field mappings and prompts.</goal>

<rules description="Non-negotiable constraints.">
<rule id="use-companion-script">Use `~/.cursor/skills/asana-task-update/scripts/asana-task-update.sh` for all Asana task mutations. Do not call raw Asana APIs directly from skills that can delegate here.</rule>
<rule id="task-required">Every operation requires `--task <task_gid>`.</rule>
<rule id="attach-requires-secret">`--attach-pr` requires `ASANA_GITHUB_SECRET`. Other operations require `ASANA_TOKEN`.</rule>
<rule id="prompt-codes">If the script exits code 2 with `PROMPT_REVIEWER` or `PROMPT_IMPLEMENTOR`, ask the user and re-run with explicit `--reviewer` or `--implementor`. Hands-off callers may instead pass `--skip-assign-if-missing` to convert missing-reviewer assignment into a non-blocking skip.</rule>
<rule id="script-timeouts">Asana updates can take time. Use `block_until_ms: 120000` for script calls.</rule>
</rules>

<usage>
```bash
# Attach only
~/.cursor/skills/asana-task-update/scripts/asana-task-update.sh \
  --task <task_gid> \
  --attach-pr --pr-url <url> --pr-title "<title>" --pr-number <num>

# Attach + assign reviewer + set review-needed status + estimate review hours
~/.cursor/skills/asana-task-update/scripts/asana-task-update.sh \
  --task <task_gid> \
  --attach-pr --pr-url <url> --pr-title "<title>" --pr-number <num> \
  --assign --set-status "Review Needed" --auto-est-review-hrs

# Hands-off attach + best-effort assign (skip if reviewer missing)
~/.cursor/skills/asana-task-update/scripts/asana-task-update.sh \
  --task <task_gid> \
  --attach-pr --pr-url <url> --pr-title "<title>" --pr-number <num> \
  --assign --skip-assign-if-missing --set-status "Review Needed" --auto-est-review-hrs

# Publish Needed -> Verification Needed (and unassign)
~/.cursor/skills/asana-task-update/scripts/asana-task-update.sh \
  --task <task_gid> \
  --set-status "Verification Needed" --unassign
```
</usage>

<step id="1" name="Build operation flags">
Determine which updates are needed by the caller and build one command with all flags:

- `--attach-pr --pr-url --pr-title --pr-number`
- `--assign` or `--assign <user_gid>`
- `--skip-assign-if-missing`
- `--unassign`
- `--set-status "Review Needed|Publish Needed|Verification Needed"`
- `--set-reviewer <user_gid>`
- `--set-implementor <user_gid>`
- `--set-priority <enum_gid>`
- `--set-planned <enum_gid>`
- `--auto-est-review-hrs`
</step>

<step id="2" name="Run update script">
Run `asana-task-update.sh` with the built flags. Prefer one call with combined operations over multiple calls.
</step>

<step id="3" name="Handle prompts">
If exit code is 2:

- `PROMPT_REVIEWER`: ask who to assign, then re-run with `--reviewer <gid>` and `--assign`
- `PROMPT_IMPLEMENTOR`: ask who to set as implementor, then re-run with `--implementor <gid>`

If the caller used `--skip-assign-if-missing`, do not ask about `PROMPT_REVIEWER` because the script will not emit it for missing-reviewer cases.
</step>

<step id="4" name="Report result">
Summarize one line per action from script output (attach result, assignment, status change, field updates).
</step>

<team-roster description="Asana user GIDs. Use numbered lists when prompting users.">
1. Jon Tzeng — `1200972350160586`
2. William Swanson — `10128869002320`
3. Paul Puey — `9976421903322`
4. Sam Holmes — `1198904591136142`
5. Matthew Piche — `522823585857811`
</team-roster>

<exit-codes>
- `0`: success
- `1`: error
- `2`: needs user input (`PROMPT_REVIEWER`, `PROMPT_IMPLEMENTOR`)
</exit-codes>
