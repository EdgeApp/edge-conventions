// edge-repo.js — Shared Edge repository utilities.
// Common functions for repo discovery, git operations, and conflict handling.
// Used by: pr-land-prepare.sh, pr-land-merge.sh, pr-land-publish.sh
const { spawnSync, execSync } = require("child_process");
const { existsSync } = require("fs");
const path = require("path");
const os = require("os");

function getRepoDir(repo) {
  const homeDir = os.homedir();
  const candidates = [
    path.join(homeDir, "git", repo),
    path.join(homeDir, "projects", repo),
    path.join(homeDir, "code", repo),
  ];
  for (const dir of candidates) {
    if (existsSync(path.join(dir, ".git"))) return dir;
  }
  return path.join(homeDir, "git", repo);
}

function getUpstreamBranch(repo) {
  return repo === "edge-react-gui" ? "origin/develop" : "origin/master";
}

function runGit(args, cwd, options = {}) {
  const { allowFailure = false } = options;
  const argArray = Array.isArray(args) ? args : args.split(" ");
  const result = spawnSync("git", argArray, {
    cwd,
    encoding: "utf8",
    env: { ...process.env, GIT_EDITOR: "true", GIT_SEQUENCE_EDITOR: ":" },
  });

  if (result.status !== 0 && !allowFailure) {
    throw new Error(
      (result.stderr || result.stdout || "Unknown git error").trim()
    );
  }

  return {
    success: result.status === 0,
    stdout: result.stdout?.trim() || "",
    stderr: result.stderr?.trim() || "",
  };
}

function parseConflictFiles(output) {
  const files = [];
  for (const line of output.split("\n")) {
    const match = line.match(/CONFLICT.*in (.+)$/);
    if (match) files.push(match[1]);
    const bothMatch = line.match(/^\s+both modified:\s+(.+)$/);
    if (bothMatch) files.push(bothMatch[1]);
  }
  return [...new Set(files)];
}

function isChangelogOnly(files) {
  return (
    files.length > 0 &&
    files.every((f) => f === "CHANGELOG.md" || f.endsWith("/CHANGELOG.md"))
  );
}

function runVerification(repoDir, baseRef, options = {}) {
  const verifyScript = path.join(
    os.homedir(),
    ".cursor",
    "skills",
    "verify-repo.sh"
  );
  const baseArg = baseRef != null ? ` --base "${baseRef}"` : "";
  const changelogArg = options.requireChangelog ? " --require-changelog" : "";
  const skipInstallArg = options.skipInstall ? " --skip-install" : "";
  try {
    execSync(
      `node "${verifyScript}" "${repoDir}"${baseArg}${changelogArg}${skipInstallArg}`,
      { stdio: "inherit", encoding: "utf8" }
    );
    return { success: true };
  } catch (e) {
    return { success: false, exitCode: e.status };
  }
}

// gh CLI wrapper for GitHub API calls
function ghApi(endpoint, options = {}) {
  const { method, body, paginate, jq } = options;
  const args = ["api", endpoint];
  if (method && method !== "GET") args.push("-X", method);
  if (paginate) args.push("--paginate");
  if (jq) args.push("--jq", jq);
  if (body) args.push("--input", "-");

  const result = spawnSync("gh", args, {
    encoding: "utf8",
    input: body ? JSON.stringify(body) : undefined,
  });

  if (result.status !== 0) {
    throw new Error(
      `gh api ${endpoint} failed: ${(result.stderr || "").trim()}`
    );
  }

  const out = result.stdout.trim();
  if (!out) return null;
  try {
    return JSON.parse(out);
  } catch {
    return out;
  }
}

function ghGraphql(query, variables = {}) {
  const args = ["api", "graphql", "-f", `query=${query}`];
  for (const [k, v] of Object.entries(variables)) {
    args.push(typeof v === "number" ? "-F" : "-f", `${k}=${v}`);
  }

  const result = spawnSync("gh", args, { encoding: "utf8" });

  if (result.status !== 0) {
    throw new Error(
      `gh api graphql failed: ${(result.stderr || "").trim()}`
    );
  }

  const parsed = JSON.parse(result.stdout);
  if (parsed.errors) {
    throw new Error(`GraphQL errors: ${JSON.stringify(parsed.errors)}`);
  }
  return parsed.data;
}

function installAndPrepare(repoDir) {
  const script = path.join(__dirname, "..", "..", "install-deps.sh");
  execSync(`"${script}" "${repoDir}"`, { stdio: "inherit" });
}

module.exports = {
  getRepoDir,
  getUpstreamBranch,
  runGit,
  parseConflictFiles,
  isChangelogOnly,
  runVerification,
  installAndPrepare,
  ghApi,
  ghGraphql,
};
