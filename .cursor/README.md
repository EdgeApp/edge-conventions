Complete agent-assisted development workflow for Edge repositories — slash commands with companion scripts, coding standards, review standards, and the author skill.

## Installation

**1. Set the required env var** in your `~/.zshrc`:
```bash
export GIT_BRANCH_PREFIX=yourname   # e.g. jon, paul, sam — used for branch naming and PR discovery
```

**2. Install files into `~/.cursor/`:**
```bash
curl -sL https://github.com/EdgeApp/edge-conventions/archive/refs/heads/jon/agents.tar.gz | \
  tar -xz --strip-components=2 -C ~/.cursor 'edge-conventions-jon-agents/.cursor' && \
  chmod +x ~/.cursor/commands/*.sh && \
  echo "✓ Installed into ~/.cursor/"
```

**3. Verify prerequisites:**
- `gh` CLI — `gh auth login`
- `jq` — `brew install jq`
- `ASANA_TOKEN` env var (Asana scripts only)

---

## Table of Contents

- [Architecture](#architecture)
- [Commands](#commands-slash-commands)
- [Companion Scripts](#companion-scripts)
- [Shared Module](#shared-module-edge-repojs)
- [Rules](#rules-mdc-files)
- [Skills](#skills)
- [Design Principles](#design-principles)

---

## Architecture

```
.cursor/
├── commands/          # Slash commands (.md) + companion scripts (.sh, .js)
├── rules/             # Coding standards (.mdc) — loaded on-demand
└── skills/            # Agent-triggered capabilities
    └── author/SKILL.md
```

**Separation of concerns:**
- **Commands** (`.md`) — Define agent workflows: steps, rules, edge cases. Invoked explicitly via `/command`.
- **Companion scripts** (`.sh`, `.js`) — Handle deterministic operations: API calls, git ops, JSON processing. Commands call scripts; scripts never call commands.
- **Rules** (`.mdc`) — Persistent coding standards loaded on-demand by file type or command step. Two classes: **editing standards** (loaded when writing code) and **review standards** (loaded during PR review).
- **Skills** (`.md`) — Specialized agent capabilities triggered by context, not explicit invocation.

All GitHub API operations use **`gh` CLI** (`gh api`, `gh api graphql`, `gh pr`). No raw `curl` + `$GITHUB_TOKEN`.

**User-specific configuration** is driven by the `GIT_BRANCH_PREFIX` env var — set once in `.zshrc`, used by scripts for branch naming (`$GIT_BRANCH_PREFIX/feature-name`) and PR discovery. No hardcoded usernames.

---

## Commands (Slash Commands)

### Core Development

| Command | Description |
|---------|-------------|
| [`/im`](.cursor/commands/im.md) | Implement an Asana task or ad-hoc feature/fix with clean, structured commits |
| [`/pr-create`](.cursor/commands/pr-create.md) | End-to-end: resolve Asana task → implement → create PR with linking |
| [`/changelog`](.cursor/commands/changelog.md) | Update CHANGELOG.md following existing patterns |
| [`/dep-pr`](.cursor/commands/dep-pr.md) | Create a dependent Asana task in another repo and run the full PR workflow |

### Code Review

| Command | Description |
|---------|-------------|
| [`/pr-review`](.cursor/commands/pr-review.md) | Review a PR against both coding and review standards |
| [`/pr-address`](.cursor/commands/pr-address.md) | Address PR feedback with fixup commits, resolving each comment after replying |
| [`/task-review`](.cursor/commands/task-review.md) | Fetch + analyze Asana task context (shared by `/im` and `/pr-create`) |

### Landing & Publishing

| Command | Description |
|---------|-------------|
| [`/pr-land`](.cursor/commands/pr-land.md) | Full landing pipeline: discover → comment check → rebase → merge → publish → Asana update |

### Analysis

| Command | Description |
|---------|-------------|
| [`/chat-audit`](.cursor/commands/chat-audit.md) | Analyze a Cursor chat export to identify inefficiencies and rule violations against the invoked command |

### Utility

| Command | Description |
|---------|-------------|
| [`/q`](.cursor/commands/q.md) | Answer questions before taking action |
| [`/author`](.cursor/commands/author.md) | Create or edit commands and skills via the author skill |

---

## Companion Scripts

### PR Operations

| Script | What it does | API |
|--------|-------------|-----|
| [`pr-create.sh`](.cursor/commands/pr-create.sh) | Create PR for current branch with auto-generated title/body | `gh pr create` |
| [`pr-address.sh`](.cursor/commands/pr-address.sh) | Fetch unresolved feedback, post replies, resolve threads, mark addressed | `gh api` REST + GraphQL |
| [`github-pr-review.sh`](.cursor/commands/github-pr-review.sh) | Fetch PR context (metadata + patches) and submit reviews | `gh pr view` + `gh api` REST |
| [`github-pr-activity.sh`](.cursor/commands/github-pr-activity.sh) | List PRs by activity (recent reviews, comments, CI status) | `gh api graphql` |

### PR Status Dashboard

| Script | What it does | API |
|--------|-------------|-----|
| [`pr-status-gql.sh`](.cursor/commands/pr-status-gql.sh) | PR status with review state, CI checks, new comments (primary) | `gh api graphql` |
| [`pr-status.sh`](.cursor/commands/pr-status.sh) | Same as above, REST fallback | `gh api` REST |
| [`pr-watch.sh`](.cursor/commands/pr-watch.sh) | TUI wrapper — auto-refresh dashboard with rate limit awareness | Delegates to above |

### PR Landing Pipeline (`/pr-land`)

These scripts run sequentially. Each handles one phase of the landing workflow:

| Script | Phase | What it does | API |
|--------|-------|-------------|-----|
| [`pr-land-discover.sh`](.cursor/commands/pr-land-discover.sh) | 1: Discovery | Find all `$GIT_BRANCH_PREFIX/*` PRs with approval status | Single `gh api graphql` query |
| [`pr-land-comments.sh`](.cursor/commands/pr-land-comments.sh) | 2: Comment check | Detect unaddressed feedback (inline threads, review bodies, top-level comments) | `gh api graphql` per PR |
| [`pr-land-prepare.sh`](.cursor/commands/pr-land-prepare.sh) | 3: Prepare | Autosquash → rebase → conflict detection → verification | Git only |
| [`verify-repo.sh`](.cursor/commands/verify-repo.sh) | 3b: Verify | CHANGELOG validation + `prepare`/`tsc`/`lint`/`test` (with `--base` and `--require-changelog` options) | Git + yarn |
| [`pr-land-merge.sh`](.cursor/commands/pr-land-merge.sh) | 5: Merge | Sequential merge with auto-rebase, mandatory verification | `gh api` REST |
| [`pr-land-publish.sh`](.cursor/commands/pr-land-publish.sh) | 6: Publish | Version bump, changelog update, commit + tag (no push) | Git + npm |

**Conflict handling is fully scripted:**
- Code conflicts → skip PR, continue with remaining
- CHANGELOG-only (including staging) → agent resolves semantically, re-runs

### Chat Analysis

| Script | What it does |
|--------|-------------|
| [`cursor-chat-extract.js`](.cursor/commands/cursor-chat-extract.js) | Parse Cursor chat export JSON into compact structured summary (messages, tool calls, stats) |

### Asana Integration

| Script | What it does | API |
|--------|-------------|-----|
| [`asana-get-context.sh`](.cursor/commands/asana-get-context.sh) | Fetch task details, attachments, subtasks, custom fields | Asana REST |
| [`asana-attach-pr.sh`](.cursor/commands/asana-attach-pr.sh) | Attach a GitHub PR URL to an Asana task | Asana REST |
| [`asana-create-dep-task.sh`](.cursor/commands/asana-create-dep-task.sh) | Create dependent task in another repo's project | Asana REST |
| [`asana-whoami.sh`](.cursor/commands/asana-whoami.sh) | Get current Asana user info | Asana REST |
| [`asana-verification-needed.sh`](.cursor/commands/asana-verification-needed.sh) | Update task status "Publish Needed" → "Verification Needed" | Asana REST (no GitHub) |

### Build & Deps

| Script | What it does |
|--------|-------------|
| [`lint-commit.sh`](.cursor/commands/lint-commit.sh) | ESLint `--fix` before commit, auto-runs `update-eslint-warnings` when available |
| [`lint-warnings.sh`](.cursor/commands/lint-warnings.sh) | Update `eslint-warnings.mdc` knowledge base from current lint output |
| [`install-deps.sh`](.cursor/commands/install-deps.sh) | Install dependencies and run prepare script |
| [`upgrade-dep.sh`](.cursor/commands/upgrade-dep.sh) | Upgrade a dependency in the GUI repo |

### Sync & Portability

| Script | What it does |
|--------|-------------|
| [`convention-sync.sh`](.cursor/commands/convention-sync.sh) | Diff and sync `~/.cursor/` files with the edge-conventions repo |
| [`tool-sync.sh`](.cursor/commands/tool-sync.sh) | Sync Cursor rules, commands, and scripts to OpenCode and Claude Code formats |
| [`port-to-opencode.sh`](.cursor/scripts/port-to-opencode.sh) | Convert Cursor `.mdc`/`.md` files to OpenCode-compatible JSON + MD mirrors |

---

## Dependency Graph

Command → script dependencies and script → script cross-references.

### Commands → Scripts

```
/im ─────────────── lint-warnings.sh
                     lint-commit.sh
                     install-deps.sh
                     verify-repo.sh
                     asana-get-context.sh

/pr-create ──────── pr-create.sh
                     lint-commit.sh
                     verify-repo.sh
                     asana-attach-pr.sh ──→ asana-whoami.sh
                     asana-get-context.sh

/pr-address ─────── pr-address.sh
                     lint-commit.sh

/pr-review ──────── github-pr-review.sh

/pr-land ────────── pr-land-discover.sh
                     pr-land-comments.sh
                     pr-land-prepare.sh ──→ edge-repo.js
                     verify-repo.sh
                     pr-land-merge.sh ────→ edge-repo.js
                     pr-land-publish.sh ──→ edge-repo.js
                     pr-land-extract-asana-task.sh
                     asana-verification-needed.sh
                     lint-commit.sh
                     upgrade-dep.sh

/dep-pr ─────────── asana-get-context.sh
                     asana-create-dep-task.sh ──→ asana-whoami.sh

/convention-sync ── convention-sync.sh

/standup ────────── asana-standup.sh ──→ asana-whoami.sh
                     github-pr-activity.sh

/chat-audit ─────── cursor-chat-extract.js

/task-review ────── asana-get-context.sh

/changelog ──────── (no scripts)
/q ──────────────── (no scripts)
/author ─────────── (no scripts)
```

### Script → Script

```
asana-attach-pr.sh ────────→ asana-whoami.sh
asana-create-dep-task.sh ──→ asana-whoami.sh
asana-standup.sh ──────────→ asana-whoami.sh
pr-watch.sh ───────────────→ pr-status-gql.sh | pr-status.sh
pr-land-prepare.sh ────────→ edge-repo.js
pr-land-merge.sh ──────────→ edge-repo.js
pr-land-publish.sh ────────→ edge-repo.js
```

### Shared Modules

```
edge-repo.js ──── Used by: pr-land-prepare.sh, pr-land-merge.sh, pr-land-publish.sh
asana-whoami.sh ─ Used by: asana-attach-pr.sh, asana-create-dep-task.sh, asana-standup.sh
```

---

## Shared Module: `edge-repo.js`

[`edge-repo.js`](.cursor/commands/edge-repo.js) eliminates duplication across the `pr-land-*` scripts. Exports:

| Function | Purpose |
|----------|---------|
| `getRepoDir(repo)` | Resolve local checkout path (`~/git/`, `~/projects/`, `~/code/`) |
| `getUpstreamBranch(repo)` | `origin/develop` for GUI, `origin/master` for everything else |
| `runGit(args, cwd, opts)` | Safe `spawnSync` wrapper with `GIT_EDITOR=true` |
| `parseConflictFiles(output)` | Extract conflicting file paths from rebase output |
| `isChangelogOnly(files)` | Check if all conflicts are in CHANGELOG.md |
| `runVerification(repoDir, baseRef, opts)` | Run the full verify script with scoped lint (supports `{requireChangelog: true}`) |
| `ghApi(endpoint, opts)` | `gh api` wrapper with method, body, paginate, jq support |
| `ghGraphql(query, vars)` | `gh api graphql` wrapper with typed variable injection |

---

## Rules (`.mdc` files)

| Rule | Activation | Purpose |
|------|-----------|---------|
| [`typescript-standards.mdc`](.cursor/rules/typescript-standards.mdc) | Loaded before editing `.ts`/`.tsx` files | TypeScript + React coding standards for **editing** (includes `simple-selectors` rule, descriptive variable names, biggystring arithmetic) |
| [`review-standards.mdc`](.cursor/rules/review-standards.mdc) | Loaded by `/pr-review` command | ~50 review-specific diagnostic rules extracted from PR history |
| [`load-standards-by-filetype.mdc`](.cursor/rules/load-standards-by-filetype.mdc) | Always applied | Auto-loads language-specific standards before editing |
| [`fix-workflow-first.mdc`](.cursor/rules/fix-workflow-first.mdc) | Always applied | Fix command/skill definitions before patching downstream symptoms |
| [`answer-questions-first.mdc`](.cursor/rules/answer-questions-first.mdc) | Always applied | Detect `?` in user messages → answer before acting; loads active command context to evaluate workflow gaps |
| [`no-format-lint.mdc`](.cursor/rules/no-format-lint.mdc) | Always applied | Don't manually fix formatting — auto-format on agent finish handles it |
| [`eslint-warnings.mdc`](.cursor/rules/eslint-warnings.mdc) | `.ts`/`.tsx` files | ESLint warning handling patterns |

**Editing vs. review separation**: `typescript-standards` contains rules for writing code (prefer `useHandler`, use `InteractionManager`, descriptive variable names, biggystring for numeric calculations). `review-standards` contains diagnostic patterns for catching bugs during review (null `tokenId` fallback, stack trace preservation, module-level cache bugs, etc.). Both are loaded together during `/pr-review`; only `typescript-standards` is loaded during editing.

---

## Skills

| Skill | Purpose |
|-------|---------|
| [`author/SKILL.md`](.cursor/skills/author/SKILL.md) | Meta-skill for creating/maintaining commands and skills. Enforces XML format, `scripts-over-reasoning`, `gh-cli-over-curl`, `minimize-context`, companion script naming conventions, `small-model-conventions`, and behavioral dependency checks during revision. |

---

## Design Principles

1. **Scripts over reasoning** — Deterministic operations (API calls, git, JSON) go in companion scripts, not inline in commands.
2. **`gh` CLI over `curl`** — All GitHub API calls use `gh api` / `gh api graphql`. Handles auth, pagination, API versioning automatically.
3. **GraphQL over REST** — Fetch only required fields in a single request where possible. Fall back to REST only when GraphQL doesn't expose the needed data (e.g., file patches).
4. **DRY shared modules** — Common utilities extracted into `edge-repo.js` rather than duplicated across scripts.
5. **XML format** — Commands use XML structure (`<goal>`, `<rules>`, `<step>`) for reliable LLM instruction-following.
6. **Standards-first** — Load coding standards before writing or reviewing any code.
7. **Fix workflow first** — When behavior is wrong, fix the command/skill definition, not the downstream symptom.
8. **No hardcoded usernames** — All user-specific values come from `GIT_BRANCH_PREFIX` env var, set once in `.zshrc`.
9. **Minimize context** — Script output must be compact and structured. Never return raw API responses. Every token costs context.
10. **Small-model conventions** — Commands that run on faster/cheaper models use verbatim bash, file-over-args, inline guardrails, and explicit parallel instructions for reliability.
11. **Knowledge base over crawling** — Maintain curated knowledge files (e.g., `eslint-warnings.mdc`) instead of having the agent crawl/grep for information repeatedly. Pre-indexed knowledge reduces tool calls and context consumption.
12. **Continuous improvement** — Workflows feed back into their own knowledge. PR review feedback updates `review-standards.mdc`, addressed warnings update `eslint-warnings.mdc`, and chat audits surface rule gaps. Each cycle reduces repetitive context gathering by the agent and repetitive review by humans.
