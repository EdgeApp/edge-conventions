# Agent Setup for Cursor

This document outlines how to set up AI-assisted development automation in Cursor for Edge development workflows.

## MCP Server Installation

Run the `/edge-conventions/install-mcp` command to install the recommended MCP servers:

- **GitHub** - PR and issue management (Docker: `ghcr.io/github/github-mcp-server`)
- **Xcode Build** - iOS build and simulator control (npm: `xcodebuildmcp`)
- **Mobile MCP** - Cross-platform device automation (npm: `@mobilenext/mobile-mcp`)

---

## Cursor Commands

Custom commands are defined in `.cursor/commands/` and can be invoked to perform complex multi-step workflows.

### codeit

Execute a planning document and iteratively refine the implementation until it passes code review.

**Usage**: Provide a freeform markdown planning document that specifies implementation steps and target repository.

**Workflow**: Stash changes → Execute plan → Build verification → iOS testing (if affects edge-react-gui or dependencies) → Review loop (max 5 iterations via `revpr`) → Restore stash

**Constraints**: Never pushes or creates PRs automatically.

---

### debugedge

Compile, launch, and debug the Edge wallet app on an iOS simulator.

**Prerequisites**: Xcode, working directory `edge-react-gui`, MCP servers `xcodebuild` and `mobile-mcp`

**Workflow**: Install deps → Clean iOS → Prepare iOS → Start Metro → Build and launch → Login if needed

**Tip**: For plugin repo debugging (edge-core-js, edge-currency-accountbased, edge-exchange-plugins, edge-currency-plugins), use `log.warn()` instead of `console.log` to see output in Metro logs.

---

### fixpr

Address reviewer comments on a pull request by creating fixup commits.

**Usage**: Provide a GitHub PR URL/number, locally edited files, or branch name.

**Workflow**: Collect comments → Confirm plan → For each comment: checkout target commit, fix, create fixup commit, cherry-pick remaining commits

**Constraints**: Does not push or auto-squash. Processes one comment at a time.

---

### packdep

Package a local dependency repo and link it to edge-react-gui for testing.

**Usage**: Specify dependency repos to package.

**Workflow**: `npm pack` → Rename with UTC timestamp → Copy to edge-react-gui → Update `package.json` reference

---

### revpr

Review code changes for quality and convention compliance.

**Usage**: Provide a GitHub PR URL, PR number, local branch name, or "current branch".

**Workflow**: Checkout code → Get diff → Launch review subagents (`review-react`, `review-errors`, `review-state`, etc.) → Compile findings → Save to `/tmp` → For PRs: submit inline comments via GitHub MCP

---

## Best Practices

1. **Monitor Metro bundler** when debugging—JavaScript logs appear there
2. **Use `log.warn()` in WebView code** since `console.log` doesn't route to Metro
3. **Test locally before pushing**—all commands work without pushing to GitHub
4. **Fixup commits preserve history**—squash them later with `git rebase -i --autosquash`
