#!/usr/bin/env node
// pr-create.sh — Creates a PR for the current branch using gh CLI.
// Usage: ./pr-create.sh [--title "PR title"] [--body-file <path>] [--draft]
// Reads from git context: repo owner/name, current branch, default branch.
// Outputs JSON with PR URL and number on success.

const { execSync, spawnSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

// Parse args
const args = process.argv.slice(2);
let title = null;
let bodyFile = null;
let draft = false;
let asanaTask = null;

for (let i = 0; i < args.length; i++) {
  if (args[i] === "--title" && args[i + 1]) title = args[++i];
  else if (args[i] === "--body-file" && args[i + 1]) bodyFile = args[++i];
  else if (args[i] === "--asana-task" && args[i + 1]) asanaTask = args[++i];
  else if (args[i] === "--draft") draft = true;
}

function git(cmd) {
  return execSync(`git ${cmd}`, { encoding: "utf8" }).trim();
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function countOccurrences(haystack, needle) {
  const matches = haystack.match(new RegExp(escapeRegExp(needle), "g"));
  return matches == null ? 0 : matches.length;
}

function hasSection(bodyText, heading) {
  return new RegExp(`^${escapeRegExp(heading)}$`, "m").test(bodyText);
}

function extractTemplateHeadings(templateBody) {
  return Array.from(templateBody.matchAll(/^### .+$/gm), match => match[0]);
}

function setChecklistValue(bodyText, label, checked) {
  const pattern = new RegExp(
    `^- \\[[ x]\\] ${escapeRegExp(label)}$`,
    "m"
  );
  return bodyText.replace(pattern, `- [${checked ? "x" : " "}] ${label}`);
}

function appendDescriptionSection(bodyText, description) {
  if (description === "") return bodyText.trimEnd();
  return `${bodyText.trimEnd()}\n\n### Description\n\n${description}`;
}

function insertAfterHeading(bodyText, heading, insertText) {
  const headingPattern = new RegExp(
    `^${escapeRegExp(heading)}\\n`,
    "m"
  );
  const match = headingPattern.exec(bodyText);
  if (match == null) return null;

  const afterHeading = match.index + match[0].length;
  const rest = bodyText.slice(afterHeading).replace(/^\n*/, "");
  return (
    bodyText.slice(0, afterHeading) +
    `\n${insertText}\n\n` +
    rest
  );
}

function buildDescriptionFromCommits() {
  try {
    const log = git(`log origin/${defaultBranch}..HEAD --format=%B---`);
    const messages = log
      .split("---")
      .map(message => message.trim())
      .filter(Boolean);

    if (messages.length === 1) {
      const parts = messages[0].split("\n").filter(Boolean);
      return parts.length > 1 ? parts.slice(1).join("\n") : "none";
    }

    return "none";
  } catch {
    return "none";
  }
}

function loadRepoTemplate() {
  const templatePath = path.join(process.cwd(), ".github", "PULL_REQUEST_TEMPLATE.md");
  if (!fs.existsSync(templatePath)) return null;

  return {
    path: templatePath,
    body: fs.readFileSync(templatePath, "utf8").replace(/\r\n/g, "\n").trim()
  };
}

function buildBodyFromTemplate(templateBody) {
  let rendered = templateBody;

  if (hasSection(rendered, "### CHANGELOG")) {
    rendered = setChecklistValue(rendered, "Yes", hasChangelog);
    rendered = setChecklistValue(rendered, "No", !hasChangelog);
  }

  const description = buildDescriptionFromCommits();
  return hasSection(rendered, "### Description")
    ? rendered
    : appendDescriptionSection(rendered, description);
}

function validateBodyForTemplate(bodyText, templateInfo) {
  if (templateInfo == null) return;

  const templateHeadings = extractTemplateHeadings(templateInfo.body);
  const missingHeadings = templateHeadings.filter(
    heading => !hasSection(bodyText, heading)
  );
  if (missingHeadings.length > 0) {
    console.error(
      "ERROR: PR body is missing required template headings from " +
        `${templateInfo.path}: ${missingHeadings.join(", ")}`
    );
    process.exit(1);
  }

  const genericSections = [];
  if (/^## Summary$/m.test(bodyText)) genericSections.push("## Summary");
  if (/^## Test plan$/m.test(bodyText)) genericSections.push("## Test plan");
  if (genericSections.length > 0) {
    console.error(
      "ERROR: PR body uses generic sections for a repo with a PR template: " +
        genericSections.join(", ")
    );
    process.exit(1);
  }
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
const normalizedRemoteUrl = remoteUrl.replace(/\/+$/, "");
const match = normalizedRemoteUrl.match(/[:/]([^/]+)\/([^/.]+?)(?:\.git)?$/);
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

let hasChangelog = false;
try {
  const diff = git(`diff origin/${defaultBranch}..HEAD -- CHANGELOG.md`);
  hasChangelog =
    diff.includes("## Unreleased") ||
    /^\+- (added|changed|fixed):/m.test(diff);
} catch {}

const templateInfo = loadRepoTemplate();

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

// Read body from file if provided
let body = bodyFile ? fs.readFileSync(bodyFile, "utf8") : null;

// Build body from template if not provided
if (!body) {
  body =
    templateInfo == null
      ? `### CHANGELOG\n\n` +
        `Does this branch warrant an entry to the CHANGELOG?\n\n` +
        `- [${hasChangelog ? "x" : " "}] Yes\n` +
        `- [${hasChangelog ? " " : "x"}] No\n\n` +
        `### Dependencies\n\nnone\n\n### Description\n\n${buildDescriptionFromCommits()}`
      : buildBodyFromTemplate(templateInfo.body);
}

validateBodyForTemplate(body, templateInfo);

// Guardrail: fail fast if the body appears to include duplicate templates.
// This prevents accidental append/concatenation from creating malformed PR descriptions.
const templateSectionCounts = {
  changelog: countOccurrences(body, "### CHANGELOG"),
  dependencies: countOccurrences(body, "### Dependencies"),
  description: countOccurrences(body, "### Description")
};
if (
  templateSectionCounts.changelog > 1 ||
  templateSectionCounts.dependencies > 1 ||
  templateSectionCounts.description > 1
) {
  console.error(
    "ERROR: PR body contains duplicated template sections. Regenerate /tmp/pr-body.md and retry."
  );
  console.error(JSON.stringify(templateSectionCounts));
  process.exit(1);
}

// Guardrail: fail fast on duplicated PR template sections.
// This catches stale/concatenated body files before creating malformed PRs.
const sectionCounts = {
  changelog: countOccurrences(body, "### CHANGELOG"),
  dependencies: countOccurrences(body, "### Dependencies"),
  description: countOccurrences(body, "### Description"),
};
if (
  sectionCounts.changelog > 1 ||
  sectionCounts.dependencies > 1 ||
  sectionCounts.description > 1
) {
  console.error(
    "ERROR: PR body appears to contain duplicated template sections. " +
      "Regenerate the body file and retry."
  );
  console.error(JSON.stringify(sectionCounts));
  process.exit(1);
}

// Inject Asana link if provided and not already present
if (asanaTask) {
  const asanaUrl = `https://app.asana.com/0/0/${asanaTask}/f`;
  const asanaRegex = new RegExp(`https://app\\.asana\\.com/\\d+/\\d+/(?:task/)?${asanaTask}`, "i");
  if (!asanaRegex.test(body)) {
    const link = `[Asana task](${asanaUrl})`;
    body =
      insertAfterHeading(body, "### Description", link) ??
      appendDescriptionSection(body, link);
  }
}

// Create PR via gh CLI — write body to a temp file to avoid arg length issues
const tmpBody = path.join(os.tmpdir(), `pr-body-${process.pid}.md`);
fs.writeFileSync(tmpBody, body, "utf8");
const ghArgs = ["pr", "create", "--title", title, "--body-file", tmpBody];
if (draft) ghArgs.push("--draft");

const result = spawnSync("gh", ghArgs, { encoding: "utf8" });
try { fs.unlinkSync(tmpBody); } catch {}
if (bodyFile && bodyFile.startsWith(os.tmpdir())) {
  try {
    fs.unlinkSync(bodyFile);
  } catch {}
}
if (result.status !== 0) {
  console.error("ERROR:", (result.stderr || "").trim());
  process.exit(1);
}

// gh pr create outputs the PR URL on stdout (--json not supported in older gh)
const prUrl = (result.stdout || "").trim();
const prMatch = prUrl.match(/\/pull\/(\d+)$/);
if (!prMatch) {
  console.error("ERROR: Could not parse PR URL from output:", prUrl);
  process.exit(1);
}

console.log(
  JSON.stringify(
    {
      url: prUrl,
      number: parseInt(prMatch[1], 10),
      title,
      base: defaultBranch,
      head: branch,
      draft,
      owner,
      repo,
    },
    null,
    2
  )
);
