---
name: standup
description: Generate a daily standup document from Asana and GitHub activity, upload to a persistent private gist. Use when the user wants to create standup notes.
compatibility: Requires gh, jq. ASANA_TOKEN for Asana integration.
metadata:
  author: j0ntz
---

<goal>Generate a daily standup document from Asana + GitHub activity, upload to a single persistent private gist.</goal>

<rules>
<rule id="links-as-titles">Task/PR names are the clickable link: `[{name}]({url})`. Never add a separate URL.</rule>
<rule id="no-reassign-in-accomplishments">Reassignment actions belong ONLY in the Handoffs section. Never list them under Accomplishments.</rule>
<rule id="single-gist">All standup files go into ONE gist with description "HUDL Notes". Create on first run, add files on subsequent runs. Never overwrite — append a suffix (`-1`, `-2`, etc.) if the filename exists.</rule>
<rule id="cleanup">Delete the local file after successful gist upload.</rule>
<rule id="script-timeout">Set `block_until_ms: 120000` for each companion script.</rule>
</rules>

<step id="1" name="Fetch activity from both sources">
Run both companion scripts **in parallel** (two Shell tool calls in one message):

```bash
scripts/asana-standup.sh
```
```bash
scripts/github-pr-activity.sh
```

If the user supplies a specific date, pass `--date YYYY-MM-DD` to both.

Capture stdout (JSON) and stderr (diagnostics) separately for each.
</step>

<step id="2" name="Merge and deduplicate">
Parse both JSON outputs. The GitHub JSON has `addressed` and `reviewed` arrays. Each entry may have an `asana_gid` field extracted from the PR body. Use it to link GitHub activity to Asana tasks:

- **GitHub `addressed` + matching Asana task** (same `asana_gid`): Add an action `{"type": "addressed_review_comments", "detail": ""}` to the matching Asana task's `actions` array. Do NOT create a separate entry.
- **GitHub `addressed` + no Asana match**: Create a new task-like entry with `actions: [{"type": "addressed_review_comments", "detail": ""}]`, using the PR title, URL, and repo as the project.
- **GitHub `reviewed` + matching Asana task**: Add an action `{"type": "reviewed_pr", "detail": "{review_state}"}` to the matching Asana task's `actions` array.
- **GitHub `reviewed` + no Asana match**: Create a new task-like entry with `actions: [{"type": "reviewed_pr", "detail": "{review_state}"}]`, using the PR title, URL, and repo as the project.
</step>

<step id="3" name="Generate markdown">
Build the markdown file with EXACTLY the structure below. Every heading, bullet, and blank line matters.

<sub-step name="3a: Header">
Line 1 of the file. Use the TARGET date (from the Asana JSON `date` field), not today.

```
# HUDL Notes — {full_weekday_name} {full_month_name} {day}, {year}
```

Example: `# HUDL Notes — Monday February 17, 2026`
</sub-step>

<sub-step name="3b: Accomplishments">
```
## Accomplishments {day_label}
```

Use `day_label` from the Asana JSON (either `"yesterday"` or `"Friday"`).

Categorize each task/PR into exactly ONE subsection based on its PRIMARY action. Determine the primary action using this priority (highest first):

1. `prd` → goes in **PR'd**
2. `addressed_pr_comments` OR `addressed_review_comments` → goes in **Addressed PR Comments**
3. `reviewed_pr` → goes in **Reviewed PRs**
4. anything else (`commented`, `completed`, `moved`, `added to project`) → goes in **General**

A task appears in only ONE subsection — the highest-priority one that matches any of its actions.

**Subsection: PR'd** — include only if at least one task qualifies.

```
### PR'd

- [{task_name}]({task_url}) ({project_name})
```

One bullet per task. No action text — the heading says it. Append `({project})` only if non-empty.

If the task ALSO has secondary actions (like `commented`), append them after ` — `:

```
- [{task_name}]({task_url}) ({project_name}) — Commented: "first 150 chars"
```

**Subsection: Addressed PR Comments** — include only if at least one task qualifies.

```
### Addressed PR Comments

- [{task_name}]({task_url}) ({project_name})
```

Same format as PR'd. Append secondary actions after ` — ` if present.

**Subsection: Reviewed PRs** — include only if at least one task qualifies.

```
### Reviewed PRs

- [{pr_title}]({pr_url}) ({repo}) — approved
```

Append the review verdict in lowercase after ` — `. Map `review_state`:
- `APPROVED` → `approved`
- `CHANGES_REQUESTED` → `changes requested`
- `COMMENTED` → `commented`

**Subsection: General** — include only if at least one task qualifies.

```
### General

- [{task_name}]({task_url}) ({project_name}) — Commented: "first 150 chars"
```

Format each action type:
- `commented` → `Commented: "{detail}"`
- `completed` → `Completed`
- `moved` → `Moved: {detail}`
- `added to project` → `Added to {detail}`

If a task has multiple actions in General, join with `; `:

```
- [{task_name}]({task_url}) ({project_name}) — Commented: "detail"; Completed
```

**Omit any subsection that would have zero bullets.**
</sub-step>

<sub-step name="3c: Goals Today">
```
## Goals Today
```

Scan the Asana `tasks` array for entries where `status` equals `"Publish Needed"`. For each, write:

```
- Publish [{task_name}]({task_url})
```

After all publish items (or immediately if there are none), add one blank bullet for the user to fill in:

```
-
```
</sub-step>

<sub-step name="3d: Handoffs">
```
## Handoffs
```

Group handoff entries by type, then by person.

**Reassignments** — group by the `detail` field (assignee name). Write one `### {assignee_name}` heading per person, then list all tasks reassigned to them:

```
### William Swanson

- [{task_name}]({task_url})

### Matthew Piche

- [{task_name}]({task_url})
```

**Blockers** — if any handoff has `kind=blocker`, add a Blocked subsection:

```
### Blocked

- [{task_name}]({task_url}) — {detail}
```

If the handoffs array is completely empty, write:

```
None
```
</sub-step>

<sub-step name="3e: Debug">
Add a horizontal rule, then a collapsed details block.

```
---

<details><summary>Debug: {N} active tasks</summary>

```

Where `{N}` is the length of the `active_tasks` array from the Asana JSON.

**Non-VN tasks**: For each entry in `active_tasks` where `status` is NOT `"Verification Needed"`, write:

```
- [{name}]({url}) — {status} ({role})
```

**VN summary**: Count entries where `status` is `"Verification Needed"`. Group by `role` and write ONE summary line:

```
- {total} tasks in Verification Needed ({M} assignee, {X} implementor, {Y} reviewer)
```

Omit role counts that are zero. Example: `- 68 tasks in Verification Needed (5 assignee, 48 implementor, 15 reviewer)`

End with the search stats and close the details tag:

```

*Searched {candidate_count} candidates, matched {task_count}*

</details>
```

`candidate_count` and `task_count` come from the Asana JSON.
</sub-step>
</step>

<step id="4" name="Upload to gist and clean up">
1. Write the markdown to `hudl-{date}.md` in the current working directory.
2. Upload to gist using this exact bash logic:

```bash
GIST_ID=$(gh gist list --limit 100 --filter "HUDL Notes" | head -1 | awk '{print $1}')
FILENAME="hudl-{date}.md"

if [ -n "$GIST_ID" ]; then
  FILES=$(gh gist view "$GIST_ID" --files)
  N=1
  BASE="hudl-{date}"
  while echo "$FILES" | grep -q "$FILENAME"; do
    N=$((N + 1))
    FILENAME="${BASE}-${N}.md"
  done
  [ "$FILENAME" != "hudl-{date}.md" ] && mv "hudl-{date}.md" "$FILENAME"
  gh gist edit "$GIST_ID" --add "$FILENAME"
else
  gh gist create --desc "HUDL Notes" "$FILENAME"
  GIST_ID=$(gh gist list --limit 1 --filter "HUDL Notes" | awk '{print $1}')
fi

rm "$FILENAME"
```

3. Present a brief summary to the user:
   - Number of accomplishment items
   - Number of handoffs
   - Gist URL: `https://gist.github.com/{username}/{GIST_ID}`
</step>
