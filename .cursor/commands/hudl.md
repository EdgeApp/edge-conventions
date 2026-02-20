<goal>Generate a daily HUDL document from GitHub PR activity, upload to a single persistent private gist.</goal>

<rules>
<rule id="links-as-titles">PR names are the clickable link: `[{title}]({url})`. Never add a separate URL.</rule>
<rule id="single-gist">All HUDL files go into ONE gist with description "HUDL Notes". Create on first run, add files on subsequent runs. Never overwrite — append a suffix (`-1`, `-2`, etc.) if the filename exists.</rule>
<rule id="cleanup">Delete the local file after successful gist upload.</rule>
<rule id="script-timeout">Set `block_until_ms: 120000` for the companion script.</rule>
<rule id="asana-cross-ref">PRs with Asana GIDs in body should have their Asana status fetched to determine true workflow status.</rule>
</rules>

<step id="1" name="Fetch PR activity">
Run the companion script:

```bash
~/.cursor/commands/github-pr-hudl.sh
```

If the user supplies a specific date, pass `--date YYYY-MM-DD`.

Capture stdout (JSON) and stderr (diagnostics) separately.
</step>

<step id="2" name="Parse and categorize">
The JSON output has these arrays:
- `created`: PRs created on target date
- `committed`: PRs where user pushed commits on target date
- `addressed`: PRs with commits after receiving review comments
- `reviewed`: PRs by others that user reviewed
- `commented`: PRs where user posted comments
- `approved`: PRs that have approval (for Goals Today)
- `blocked`: PRs blocked by CI failure or changes requested (for Handoffs)
- `open_prs`: All open PRs for debug section

Each entry has: `pr_number`, `pr_title`, `pr_url`, `repo`, `asana_gid` (nullable), `asana_status` (nullable), plus action-specific fields.
</step>

<step id="3" name="Generate markdown">
Build the markdown file with EXACTLY the structure below. Every heading, bullet, and blank line matters.

<sub-step name="3a: Header">
Line 1 of the file. Use the TARGET date from the JSON `date` field.

```
# HUDL Notes — {full_weekday_name} {full_month_name} {day}, {year}
```

Example: `# HUDL Notes — Monday February 17, 2026`
</sub-step>

<sub-step name="3b: Accomplishments">
```
## Accomplishments {day_label}
```

Use `day_label` from the JSON (either `"yesterday"` or `"Friday"`).

Categorize each PR into exactly ONE subsection based on its PRIMARY action. Determine the primary action using this priority (highest first):

1. `created` → goes in **PR'd**
2. `addressed` → goes in **Addressed PR Comments**
3. `reviewed` → goes in **Reviewed PRs**
4. `committed` or `commented` → goes in **General**

A PR appears in only ONE subsection — the highest-priority one that matches.

**Subsection: PR'd** — include only if at least one PR qualifies.

```
### PR'd

- [{pr_title}]({pr_url}) ({repo})
```

One bullet per PR. No action text — the heading says it.

**Subsection: Addressed PR Comments** — include only if at least one PR qualifies.

```
### Addressed PR Comments

- [{pr_title}]({pr_url}) ({repo})
```

**Subsection: Reviewed PRs** — include only if at least one PR qualifies.

```
### Reviewed PRs

- [{pr_title}]({pr_url}) ({repo}) — approved
```

Append the review verdict in lowercase after ` — `. Map `review_state`:
- `APPROVED` → `approved`
- `CHANGES_REQUESTED` → `changes requested`
- `COMMENTED` → `commented`

**Subsection: General** — include only if at least one PR qualifies.

```
### General

- [{pr_title}]({pr_url}) ({repo}) — Committed: 3 commits
```

Format each action type:
- `committed` → `Committed: {commit_count} commits`
- `commented` → `Commented`

If a PR has multiple actions in General, join with `; `.

**Omit any subsection that would have zero bullets.**
</sub-step>

<sub-step name="3c: Goals Today">
```
## Goals Today
```

List PRs from the `approved` array (PRs that are approved and ready to merge/publish):

```
- Publish [{pr_title}]({pr_url})
```

After all approved items (or immediately if there are none), add one blank bullet for the user to fill in:

```
-
```
</sub-step>

<sub-step name="3d: Handoffs">
```
## Handoffs
```

Group entries from the `blocked` array by block reason.

**CI Failures** — if any PR has `block_reason=ci_failure`:

```
### Blocked by CI

- [{pr_title}]({pr_url}) — CI failing
```

**Changes Requested** — if any PR has `block_reason=changes_requested`:

```
### Changes Requested

- [{pr_title}]({pr_url}) — {reviewer} requested changes
```

If the blocked array is completely empty, write:

```
None
```
</sub-step>

<sub-step name="3e: Debug">
Add a horizontal rule, then a collapsed details block.

```
---

<details><summary>Debug: {N} open PRs</summary>

```

Where `{N}` is the length of the `open_prs` array.

For each entry in `open_prs`, write:

```
- [{pr_title}]({pr_url}) — {status_summary}
```

Where `status_summary` includes: review state, CI status, Asana status (if present).

End with search stats and close the details tag:

```

*Searched {search_count} PRs*

</details>
```

`search_count` comes from the JSON.
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
