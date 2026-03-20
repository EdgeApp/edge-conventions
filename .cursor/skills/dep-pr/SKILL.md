---
name: dep-pr
description: Create a dependent Asana task in another repo and run the full PR workflow for it. Use when the user needs cross-repo dependent task creation.
compatibility: Requires git, gh, node, jq. ASANA_TOKEN for Asana integration.
metadata:
  author: j0ntz
---

<goal>Create a dependent Asana task in another repo and run the full PR workflow for it — automating cross-repo task creation, dependency linking, implementation, and PR creation.</goal>

<rules description="Non-negotiable constraints.">
<rule id="parent-required">A parent Asana task URL is always required. It provides context, project placement, and dependency linking.</rule>
<rule id="check-existence">Always check if a dependent task already exists before creating one. The script handles this — respect the `CREATED: false` output.</rule>
<rule id="script-timeouts">Asana scripts can take up to 90s. Always set `block_until_ms: 120000`.</rule>
<rule id="no-impl-before-task">Do NOT begin implementation until the dependent task is created and linked.</rule>
<rule id="same-project">The dependent task MUST be created in the same project(s) as the parent task, including release-version project tags (for example `4.46.0`). The script handles this automatically by copying all parent project memberships.</rule>
<rule id="initial-assignee">The dependent task is automatically assigned to the current user (resolved via `asana-whoami.sh`). Do NOT hardcode a user GID — omit `--assignee` to let the script auto-resolve.</rule>
</rules>

<dependency-hierarchy description="Repo dependency structure. Lower-level repos block higher-level repos.">
The Edge repos have a layered dependency structure:

```
core  (lowest — types, APIs, runtime)
  ↑
accb / exch  (middle — currency and exchange plugins, depend on core)
  ↑
gui  (highest — UI, depends on all others)
```

**Dependency direction rule**: When creating a dependent task for a repo at a **lower or equal** level, the new task **blocks** the parent task. This is the standard case — e.g., an `accb:` task blocks the `gui:` parent because the plugin change must land first.

If the target repo is at a **higher** level than the parent (e.g., creating a `gui:` task from an `accb:` parent), this is unusual. Ask the user to confirm before proceeding — the dependency direction may need to be reversed (parent blocks the new task instead).

| Level | Repos |
|-------|-------|
| 3 (highest) | `gui` |
| 2 | `accb`, `exch` |
| 1 (lowest) | `core` |

</dependency-hierarchy>

<repo-map description="Shorthand prefixes to repo directories and branch bases.">

| Prefix | Repository | Directory | Branch from |
|--------|-----------|-----------|-------------|
| `gui` | `edge-react-gui` | `~/git/edge-react-gui` | `develop` |
| `exch` | `edge-exchange-plugins` | `~/git/edge-exchange-plugins` | `master` |
| `accb` | `edge-currency-accountbased` | `~/git/edge-currency-accountbased` | `master` |
| `core` | `edge-core-js` | `~/git/edge-core-js` | `master` |

</repo-map>

<step id="1" name="Resolve parent task and target repo">
The user provides a parent Asana task URL and a target repo (as a prefix or full name).

1. **Extract the parent task GID** from the URL.
2. **Fetch parent task context** using `asana-get-context.sh` to understand what work is needed.
3. **Determine the target repo** from the user's input. If not specified, ask.
4. **Validate dependency direction** using the hierarchy table. If the target is at a higher level than the parent, warn and ask for confirmation.
</step>

<step id="2" name="Create dependent task">
Derive the dependent task name from the parent: `<target-prefix>: <parent task name without its prefix>`.

If the parent task name already has a prefix (e.g. `gui: Some feature`), strip it and replace with the target prefix. If no prefix, prepend the target prefix.

```bash
~/.cursor/skills/dep-pr/scripts/asana-create-dep-task.sh \
  --parent <parent_gid> \
  --name "<prefix>: <task name>" \
  --notes "<description referencing parent task>"
```

The script:
- Checks if a matching dependency already exists (by name) — if so, outputs `CREATED: false` and the existing GID
- Creates the task in all parent project memberships (including release-version tags)
- Copies priority, status, and `Planned` from the parent
- Assigns to the current user (auto-resolved via `asana-whoami.sh`)
- Sets the new task as a blocking dependency of the parent

If `CREATED: false`, report the existing task to the user and continue with the existing GID.
</step>

<step id="3" name="Implement and PR">
Delegate to the `pr-create.md` workflow using the **new** (or existing) task URL:

1. `cd` to the target repo directory (see repo-map).
2. **Read `~/.cursor/skills/pr-create/SKILL.md` now** (use the Read tool — do NOT skip this). Then follow its steps 1-6 (push, verify, build PR description, create PR, optional Asana updates, report).

The Asana task context from step 1 provides the implementation requirements. The agent already has full context from the parent task.
</step>

<step id="4" name="Report">
Display both the new Asana task and the PR as clickable links. Note the dependency relationship.
</step>

<edge-cases>
<case name="Dependent task already exists">The script detects this. Report: "Found existing dependent task: [link]. Continuing with PR workflow." Then proceed to step 3.</case>
<case name="Parent task has no project">The script falls back to the first available project. Warn the user if the placement looks wrong.</case>
<case name="Target repo already has a matching branch">Step 3 delegates to `pr-create.md` which handles branch state assessment.</case>
<case name="Upward dependency (higher-level target)">Ask: "Creating a [gui] task from a [core] parent is unusual — the dependency direction would be reversed. Confirm? (yes/no)"</case>
</edge-cases>
