#!/usr/bin/env node
// pr-create.sh — Creates a PR for the current branch using gh CLI.
// Usage: ./pr-create.sh [--title "PR title"] [--body "PR body"] [--draft]
// Reads from git context: repo owner/name, current branch, default branch.
// Outputs JSON with PR URL and number on success.

const { execSync, spawnSync } = require("child_process");

// Parse args
const args = process.argv.slice(2);
let title = null;
let body = null;
let draft = false;

for (let i = 0; i < args.length; i++) {
  if (args[i] === "--title" && args[i + 1]) title = args[++i];
  else if (args[i] === "--body" && args[i + 1]) body = args[++i];
  else if (args[i] === "--draft") draft = true;
}

function git(cmd) {
  return execSync(`git ${cmd}`, { encoding: "utf8" }).trim();
}

function requireGh() {
  const check = spawnSync("gh", ["auth", "status"], { encoding: "utf8" });
  if (check.status !== 0) {
    console.error("PROMPT_GH_AUTH");
    process.exit(2);
  }
}

requireGh();

// Detect repo info from git
const remoteUrl = git("remote get-url origin");
const match = remoteUrl.match(/[:/]([^/]+)\/([^/.]+?)(?:\.git)?$/);
if (!match) {
  console.error("ERROR: Could not parse owner/repo from remote:", remoteUrl);
  process.exit(1);
}
const [, owner, repo] = match;

const branch = git("rev-parse --abbrev-ref HEAD");
if (["master", "develop", "HEAD"].includes(branch)) {
  console.error(
    `ERROR: Cannot create PR from '${branch}'. Switch to a feature branch.`
  );
  process.exit(1);
}

// Detect default branch
let defaultBranch;
try {
  defaultBranch = git(
    "symbolic-ref --quiet --short refs/remotes/origin/HEAD"
  ).replace("origin/", "");
} catch {
  try {
    const show = execSync("git remote show origin", { encoding: "utf8" });
    defaultBranch =
      show.match(/HEAD branch:\s*(.+)/)?.[1]?.trim() || "master";
  } catch {
    defaultBranch = "master";
  }
}

// Build title from commits/branch if not provided
if (!title) {
  try {
    const commits = git(`log origin/${defaultBranch}..HEAD --oneline`)
      .split("\n")
      .filter(Boolean);
    if (commits.length === 1) {
      title = commits[0].replace(/^[a-f0-9]+\s+/, "");
    } else {
      title = branch
        .replace(/^jon\//, "")
        .replace(/^fix\//, "Fix: ")
        .replace(/^feat\//, "")
        .replace(/[-_]/g, " ")
        .replace(/^\w/, (c) => c.toUpperCase());
    }
  } catch {
    title = branch;
  }
}

// Build body from template if not provided
if (!body) {
  const isGui = repo === "edge-react-gui";
  let hasChangelog = false;
  try {
    const diff = git(`diff origin/${defaultBranch}..HEAD -- CHANGELOG.md`);
    hasChangelog =
      diff.includes("## Unreleased") ||
      /^\+- (added|changed|fixed):/m.test(diff);
  } catch {}

  const yes = hasChangelog ? "x" : " ";
  const no = hasChangelog ? " " : "x";

  body =
    `### CHANGELOG\n\n` +
    `Does this branch warrant an entry to the CHANGELOG?\n\n` +
    `- [${yes}] Yes\n- [${no}] No\n\n` +
    `### Dependencies\n\nnone\n\n### Description\n\n`;

  try {
    const log = git(`log origin/${defaultBranch}..HEAD --format=%B---`);
    const messages = log
      .split("---")
      .map((m) => m.trim())
      .filter(Boolean);
    if (messages.length === 1) {
      const parts = messages[0].split("\n").filter(Boolean);
      body += parts.length > 1 ? parts.slice(1).join("\n") : "none";
    } else {
      body += "none";
    }
  } catch {
    body += "none";
  }

  if (isGui) {
    body +=
      `\n\n### Requirements\n\n` +
      `If you have made **any** visual changes to the GUI. Make sure you have:\n\n` +
      `- [ ] Tested on iOS device\n` +
      `- [ ] Tested on Android device\n` +
      `- [ ] Tested on small-screen device (iPod Touch)\n` +
      `- [ ] Tested on large-screen device (tablet)`;
  }
}

// Create PR via gh CLI — handles push check, existing-PR check, etc.
const ghArgs = [
  "pr",
  "create",
  "--title",
  title,
  "--body",
  body,
  "--json",
  "number,title,url,headRefName,baseRefName,isDraft",
];
if (draft) ghArgs.push("--draft");

const result = spawnSync("gh", ghArgs, { encoding: "utf8" });
if (result.status !== 0) {
  console.error("ERROR:", (result.stderr || "").trim());
  process.exit(1);
}

const pr = JSON.parse(result.stdout);
console.log(
  JSON.stringify(
    {
      url: pr.url,
      number: pr.number,
      title: pr.title,
      base: pr.baseRefName,
      head: pr.headRefName,
      draft: pr.isDraft,
      owner,
      repo,
    },
    null,
    2
  )
);
