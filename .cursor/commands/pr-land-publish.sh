#!/usr/bin/env node
// pr-land-publish.sh
// Version bump, changelog update, commit, and tag for npm publishing
// Usage: echo '[{"repo":"edge-exchange-plugins","branch":"master"}]' | ./pr-land-publish.sh
//
// How it works:
//   1. Checks out the branch and fetches latest
//   2. Parses CHANGELOG.md for unreleased entries
//   3. Runs verification (yarn verify or yarn tsc && yarn lint)
//   4. Bumps version (minor for added/changed, patch for fixed)
//   5. Updates CHANGELOG.md with version header
//   6. Commits and tags locally (does NOT push)
//   7. Returns JSON with needsPush flag
//
// The agent should:
//   - Show the user the version bump details and ask for confirmation
//   - If confirmed, push master + tag to origin
//   - Then prompt the user to run `npm publish` in a real terminal
//
// Exit codes:
//   0 = Version bumped, committed, tagged (check needsPush in JSON)
//   1 = Verification failed
//   2 = No unreleased changes

const { execSync } = require("child_process");
const { existsSync, readFileSync, writeFileSync } = require("fs");
const path = require("path");
const { getRepoDir, runGit: _runGit, installAndPrepare } = require(path.join(__dirname, "edge-repo.js"));

// Thin wrapper: publish only needs the stdout string from runGit
function runGit(args, cwd) {
  return _runGit(typeof args === "string" ? args.split(" ") : args, cwd).stdout;
}

function parseChangelog(repoDir) {
  const changelogPath = path.join(repoDir, "CHANGELOG.md");
  if (!existsSync(changelogPath)) {
    return { entries: [], patchOnly: true, error: "No CHANGELOG.md found" };
  }
  
  const content = readFileSync(changelogPath, "utf8");
  const unreleasedStart = content.indexOf("## Unreleased");
  
  if (unreleasedStart === -1) {
    return { entries: [], patchOnly: true, error: "No ## Unreleased section" };
  }
  
  const nextVersionStart = content.indexOf("## ", unreleasedStart + "## Unreleased".length);
  const unreleasedSection = content.substring(
    unreleasedStart + "## Unreleased".length,
    nextVersionStart !== -1 ? nextVersionStart : undefined
  ).trim();
  
  const entries = unreleasedSection.split("\n")
    .map(line => line.trim())
    .filter(line => line.length > 0 && !line.startsWith("## "));
  
  if (entries.length === 0) {
    return { entries: [], patchOnly: true, error: "No entries in Unreleased section" };
  }
  
  // Validate entries and determine version bump
  const allowedTags = ["- added:", "- changed:", "- deprecated:", "- removed:", "- fixed:", "- security:"];
  let patchOnly = true;
  
  for (const entry of entries) {
    const hasValidTag = allowedTags.some(tag => entry.startsWith(tag));
    if (!hasValidTag) {
      return { entries, patchOnly: true, error: `Invalid entry format: ${entry}` };
    }
    
    // Minor version bump for added/changed
    if (entry.startsWith("- added:") || entry.startsWith("- changed:")) {
      patchOnly = false;
    }
  }
  
  return { entries, patchOnly, error: null };
}

function bumpVersion(repoDir, patchOnly) {
  const pkgPath = path.join(repoDir, "package.json");
  const pkg = JSON.parse(readFileSync(pkgPath, "utf8"));
  const parts = pkg.version.split(".").map(Number);
  
  if (patchOnly) {
    parts[2]++;
  } else {
    parts[1]++;
    parts[2] = 0;
  }
  
  const newVersion = parts.join(".");
  pkg.version = newVersion;
  writeFileSync(pkgPath, JSON.stringify(pkg, null, 2) + "\n");
  
  return { oldVersion: pkg.version, newVersion };
}

function updateChangelog(repoDir, newVersion) {
  const changelogPath = path.join(repoDir, "CHANGELOG.md");
  let content = readFileSync(changelogPath, "utf8");
  
  const date = new Date().toISOString().split("T")[0];
  const newHeading = `## ${newVersion} (${date})`;
  
  content = content.replace(
    "## Unreleased",
    `## Unreleased\n\n${newHeading}`
  );
  
  writeFileSync(changelogPath, content);
}

function checkNpmPublished(packageName, version) {
  try {
    const info = execSync(`npm view ${packageName}@${version} version`, { 
      encoding: "utf8", 
      stdio: "pipe" 
    }).trim();
    return info === version;
  } catch (e) {
    return false;
  }
}

async function publishRepo(repo, branch) {
  const repoDir = getRepoDir(repo);
  const results = {
    repo,
    branch,
    repoDir,
    success: false
  };
  
  console.error(`\n=== Publishing ${repo} ===`);
  console.error(`Directory: ${repoDir}`);
  
  // 1. Ensure we're on the right branch and up to date
  try {
    runGit("fetch origin", repoDir);
    runGit(`checkout ${branch}`, repoDir);
    runGit(`reset --hard origin/${branch}`, repoDir);
  } catch (e) {
    results.error = `Git checkout failed: ${e.message}`;
    return results;
  }
  
  // 2. Get current package info
  const pkgPath = path.join(repoDir, "package.json");
  const currentPkg = JSON.parse(readFileSync(pkgPath, "utf8"));
  const currentVersion = currentPkg.version;
  const packageName = currentPkg.name;
  
  // 3. Check if current version is already published
  const isPublished = checkNpmPublished(packageName, currentVersion);
  
  if (isPublished) {
    // Version already published - do full version bump flow
    const changelog = parseChangelog(repoDir);
    if (changelog.error) {
      results.error = changelog.error;
      results.exitCode = 2;
      return results;
    }
    
    console.error(`\nChangelog entries (${changelog.entries.length}):`);
    for (const entry of changelog.entries) {
      console.error(`  ${entry}`);
    }
    console.error(`\nVersion bump: ${changelog.patchOnly ? "PATCH" : "MINOR"}`);
    
    // Run verification
    console.error("\nRunning verification...");
    try {
      installAndPrepare(repoDir);

      const pkg = JSON.parse(readFileSync(pkgPath, "utf8"));
      if (pkg.scripts?.verify) {
        execSync("yarn verify", { cwd: repoDir, stdio: "inherit" });
      } else {
        execSync("yarn tsc && yarn lint", { cwd: repoDir, stdio: "inherit" });
      }
    } catch (e) {
      results.error = "Verification failed";
      results.exitCode = 1;
      return results;
    }
    console.error("✓ Verification passed");
    
    // Bump version
    const { newVersion } = bumpVersion(repoDir, changelog.patchOnly);
    console.error(`\nVersion: ${currentVersion} → ${newVersion}`);
    
    // Update changelog
    updateChangelog(repoDir, newVersion);
    console.error("✓ Updated CHANGELOG.md");
    
    // Commit and tag (do NOT push yet - agent will prompt user first)
    try {
      runGit("add package.json CHANGELOG.md", repoDir);
      execSync(`git commit -m "v${newVersion}" --no-verify`, { cwd: repoDir, stdio: "pipe" });
      runGit(`tag v${newVersion}`, repoDir);
      console.error(`✓ Committed and tagged v${newVersion}`);
    } catch (e) {
      results.error = `Git commit failed: ${e.message}`;
      return results;
    }
    
    results.newVersion = newVersion;
    results.needsPush = true;
    results.success = true;
    return results;
  } else {
    // Current version NOT published - check if already pushed
    console.error(`\nVersion ${currentVersion} not yet published to npm`);
    
    let alreadyPushed = false;
    try {
      const remoteTags = runGit(`ls-remote --tags origin v${currentVersion}`, repoDir);
      alreadyPushed = remoteTags.length > 0;
    } catch (e) {
      // ls-remote failed, assume not pushed
    }
    
    results.newVersion = currentVersion;
    results.needsPush = !alreadyPushed;
    
    if (alreadyPushed) {
      console.error("Tag already pushed to origin.");
    } else {
      console.error("Version bump exists locally but has not been pushed yet.");
    }
    
    results.success = true;
    return results;
  }
}

async function main() {
  let input = "";
  for await (const chunk of process.stdin) {
    input += chunk;
  }
  
  const repos = JSON.parse(input);
  const results = {
    published: [],
    failed: [],
    skipped: []
  };
  
  let exitCode = 0;
  
  for (const { repo, branch } of repos) {
    const result = await publishRepo(repo, branch || "master");
    
    if (result.success) {
      results.published.push(result);
    } else if (result.exitCode === 2) {
      results.skipped.push(result);
    } else {
      results.failed.push(result);
      exitCode = result.exitCode || 1;
    }
  }
  
  // Summary
  console.error("\n=== Publish Summary ===");
  if (results.published.length > 0) {
    console.error(`Ready (${results.published.length}):`);
    for (const r of results.published) {
      console.error(`  ✓ ${r.repo}@${r.newVersion}${r.needsPush ? " (needs push)" : " (already pushed)"}`);
    }
  }
  if (results.skipped.length > 0) {
    console.error(`Skipped (${results.skipped.length}):`);
    for (const r of results.skipped) {
      console.error(`  ⏭ ${r.repo}: ${r.error}`);
    }
  }
  if (results.failed.length > 0) {
    console.error(`Failed (${results.failed.length}):`);
    for (const r of results.failed) {
      console.error(`  ✗ ${r.repo}: ${r.error}`);
    }
  }
  
  console.log(JSON.stringify(results, null, 2));
  process.exit(exitCode);
}

main().catch(e => { console.error(e); process.exit(1); });
