#!/usr/bin/env node
// verify-repo.sh
// Runs full verification: CHANGELOG + code verification (prepare, tsc, lint, test)
// Usage: ./verify-repo.sh [repo-dir] [--base <upstream-ref>]
// If repo-dir not provided, uses current directory
// If --base is provided, lint is scoped to files changed vs that ref
//
// Exit codes:
//   0 = All verification passed
//   1 = Code verification failed (prepare/tsc/lint/test)
//   2 = CHANGELOG verification failed

const { execSync } = require("child_process");
const { readFileSync, existsSync } = require("fs");
const path = require("path");

// Parse arguments: positional repo-dir + optional --base <ref>
let repoDir = process.cwd();
let baseRef = null;
const args = process.argv.slice(2);
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--base" && i + 1 < args.length) {
    baseRef = args[++i];
  } else if (!args[i].startsWith("--")) {
    repoDir = args[i];
  }
}

const packageJsonPath = path.join(repoDir, "package.json");
const changelogPath = path.join(repoDir, "CHANGELOG.md");

// Detect repo type
const isGui = repoDir.includes("edge-react-gui");

console.log("=== Pre-Merge Verification ===");
console.log(`Directory: ${repoDir}`);
console.log("");

// ============================================
// CHANGELOG Verification
// ============================================

function verifyChangelog() {
  if (!existsSync(changelogPath)) {
    console.log("⏭  CHANGELOG verification - skipped (no CHANGELOG.md)");
    return { success: true, skipped: true };
  }

  console.log("▶  CHANGELOG verification...");
  
  let content;
  try {
    content = readFileSync(changelogPath, "utf8");
  } catch (e) {
    console.error(`✗  Failed to read CHANGELOG.md: ${e.message}`);
    return { success: false, error: e.message };
  }

  const lines = content.split("\n");
  const errors = [];
  const warnings = [];
  let hasStagingSection = false;
  let hasUnreleasedSection = false;
  let inUnreleasedSection = false;
  let inStagingSection = false;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const lineNum = i + 1;

    // Check for conflict markers
    if (line.startsWith("<<<<<<<") || line.startsWith("=======") || 
        line.startsWith(">>>>>>>") || line.startsWith("|||||||")) {
      errors.push(`Line ${lineNum}: Unresolved conflict marker: "${line.slice(0, 40)}..."`);
    }

    // Track section headers
    if (line.match(/^## Unreleased/i)) {
      hasUnreleasedSection = true;
      inUnreleasedSection = true;
      inStagingSection = false;
    } else if (line.match(/^## .+\(staging\)/i)) {
      hasStagingSection = true;
      inUnreleasedSection = false;
      inStagingSection = true;
    } else if (line.match(/^## \d+\.\d+\.\d+/)) {
      inUnreleasedSection = false;
      inStagingSection = false;
    }

    // Check entry format in unreleased/staging sections
    if ((inUnreleasedSection || inStagingSection) && line.startsWith("- ")) {
      if (!line.match(/^- (added|changed|fixed|deprecated|removed|security):/i)) {
        warnings.push(`Line ${lineNum}: Entry may not follow "- type: description" format`);
      }
    }

    // Check for empty or malformed list items
    if (line.match(/^-\s*$/)) {
      errors.push(`Line ${lineNum}: Empty list item found`);
    }
    if (line.match(/^--/) || line.match(/^- -/)) {
      errors.push(`Line ${lineNum}: Malformed list item`);
    }
  }

  if (!hasUnreleasedSection && !hasStagingSection) {
    errors.push("No '## Unreleased' or staging section found");
  }

  if (errors.length > 0) {
    console.error("✗  CHANGELOG verification - FAILED");
    for (const e of errors) {
      console.error(`   ${e}`);
    }
    return { success: false, errors };
  }

  if (warnings.length > 0) {
    console.log("✓  CHANGELOG verification - passed (with warnings)");
    for (const w of warnings) {
      console.log(`   ⚠  ${w}`);
    }
  } else {
    console.log("✓  CHANGELOG verification - passed");
  }

  if (hasStagingSection && isGui) {
    console.log("   ℹ  Note: This repo has a staging section");
  }

  return { success: true, hasStagingSection };
}

// ============================================
// Code Verification
// ============================================

function verifyCode() {
  if (!existsSync(packageJsonPath)) {
    console.log("⏭  Code verification - skipped (no package.json)");
    return { success: true, skipped: true };
  }

  let pkg;
  try {
    pkg = JSON.parse(readFileSync(packageJsonPath, "utf8"));
  } catch (e) {
    console.error(`✗  Failed to parse package.json: ${e.message}`);
    return { success: false, error: e.message };
  }

  const scripts = pkg.scripts || {};
  const commands = ["prepare", "tsc", "lint", "test"];

  console.log("");
  console.log("Code verification:");

  for (const cmd of commands) {
    if (scripts[cmd] == null) {
      console.log(`⏭  yarn ${cmd} - skipped (not in package.json)`);
      continue;
    }

    // When a base ref is provided, scope lint to only files changed by the branch
    if (cmd === "lint" && baseRef != null) {
      let changedFiles;
      try {
        changedFiles = execSync(
          `git diff --name-only --diff-filter=ACMR ${baseRef}...HEAD -- '*.ts' '*.tsx' '*.js' '*.jsx'`,
          { cwd: repoDir, encoding: "utf8" }
        ).trim();
      } catch (e) {
        console.error(`✗  Failed to determine changed files for lint: ${e.message}`);
        return { success: false, failedStep: "lint (changed files)" };
      }

      if (changedFiles.length === 0) {
        console.log("⏭  yarn lint - skipped (no lintable files changed)");
        continue;
      }

      const fileList = changedFiles.split("\n").map(f => `"${f}"`).join(" ");
      const fileCount = changedFiles.split("\n").length;
      console.log(`▶  eslint (${fileCount} changed file${fileCount === 1 ? "" : "s"} vs ${baseRef})...`);
      try {
        execSync(`npx eslint ${fileList}`, {
          cwd: repoDir,
          stdio: "inherit",
          env: { ...process.env, FORCE_COLOR: "1" }
        });
        console.log(`✓  eslint (changed files) - passed\n`);
        continue;
      } catch (e) {
        console.error(`✗  eslint (changed files) - FAILED\n`);
        return { success: false, failedStep: "eslint (changed files)" };
      }
    }

    console.log(`▶  yarn ${cmd}...`);
    try {
      execSync(`yarn ${cmd}`, {
        cwd: repoDir,
        stdio: "inherit",
        env: { ...process.env, FORCE_COLOR: "1" }
      });
      console.log(`✓  yarn ${cmd} - passed\n`);
    } catch (e) {
      console.error(`✗  yarn ${cmd} - FAILED\n`);
      return { success: false, failedStep: `yarn ${cmd}` };
    }
  }

  return { success: true };
}

// ============================================
// Main
// ============================================

const changelogResult = verifyChangelog();
if (!changelogResult.success) {
  console.error("\n=== Verification FAILED (CHANGELOG) ===");
  process.exit(2);
}

const codeResult = verifyCode();
if (!codeResult.success) {
  console.error("\n=== Verification FAILED (Code) ===");
  console.error(`Failed step: ${codeResult.failedStep || codeResult.error}`);
  process.exit(1);
}

console.log("\n=== Verification PASSED ===");
process.exit(0);
