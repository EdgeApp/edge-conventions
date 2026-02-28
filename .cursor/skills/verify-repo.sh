#!/usr/bin/env node
// verify-repo.sh
// Runs full verification: CHANGELOG + code verification (prepare, tsc, lint, test)
// Usage: ./verify-repo.sh [repo-dir] [--base <upstream-ref>] [--skip-install]
// If repo-dir not provided, uses current directory
// If --base is provided, lint is scoped to files changed vs that ref
// If --skip-install is provided, skips the initial `yarn` dependency install
//
// Exit codes:
//   0 = All verification passed
//   1 = Code verification failed (prepare/tsc/lint/test)
//   2 = CHANGELOG verification failed

const { execSync } = require("child_process");
const { readFileSync, existsSync, writeFileSync } = require("fs");
const path = require("path");
const os = require("os");

// Parse arguments: positional repo-dir + optional --base <ref> + optional --require-changelog
let repoDir = process.cwd();
let baseRef = null;
let requireChangelog = false;
let skipInstall = false;
const args = process.argv.slice(2);
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--base" && i + 1 < args.length) {
    baseRef = args[++i];
  } else if (args[i] === "--require-changelog") {
    requireChangelog = true;
  } else if (args[i] === "--skip-install") {
    skipInstall = true;
  } else if (!args[i].startsWith("--")) {
    repoDir = args[i];
  }
}

const packageJsonPath = path.join(repoDir, "package.json");
const changelogPath = path.join(repoDir, "CHANGELOG.md");

function sanitizeLabel(label) {
  return label.replace(/[^a-z0-9]/gi, "-").replace(/-+/g, "-").replace(/^-|-$/g, "");
}

function runCommandWithLog(command, label, repoDir) {
  const safeLabel = sanitizeLabel(label || command);
  const logPath = path.join(os.tmpdir(), `verify-${safeLabel}-${Date.now()}-${Math.random().toString(36).slice(2)}.log`);
  try {
    const output = execSync(command, {
      cwd: repoDir,
      encoding: "utf8",
      stdio: "pipe",
      env: { ...process.env, FORCE_COLOR: "1" },
    });
    writeFileSync(logPath, output);
    return { success: true, logPath };
  } catch (error) {
    const stdout = error.stdout ? error.stdout.toString() : "";
    const stderr = error.stderr ? error.stderr.toString() : "";
    writeFileSync(logPath, stdout + stderr);
    return { success: false, logPath, error };
  }
}

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

  const TYPE_ORDER = ["added", "changed", "deprecated", "fixed", "removed", "security"];

  function entryType(line) {
    const m = line.match(/^- (\w+):/i);
    return m ? m[1].toLowerCase() : null;
  }

  let currentSection = null;
  let sectionEntries = [];
  let sectionStartLine = 0;

  function validateSection() {
    if (currentSection == null) return;
    const isActive = currentSection === "unreleased" || currentSection === "staging";
    if (!isActive) return;

    // Empty section check removed — emptiness is validated per-PR via --require-changelog

    const seen = new Set();
    for (const { text, lineNum } of sectionEntries) {
      const normalized = text.replace(/\s+/g, " ").trim();
      if (seen.has(normalized)) {
        errors.push(`Line ${lineNum}: Duplicate entry in ${currentSection}: "${text.slice(0, 60)}..."`);
      }
      seen.add(normalized);
    }

    let lastTypeIdx = -1;
    for (const { text, lineNum } of sectionEntries) {
      const type = entryType(text);
      if (type == null) continue;
      const idx = TYPE_ORDER.indexOf(type);
      if (idx === -1) continue;
      if (idx < lastTypeIdx) {
        const expected = TYPE_ORDER[lastTypeIdx];
        errors.push(`Line ${lineNum}: "${type}" entry after "${expected}" in ${currentSection} — expected order: ${TYPE_ORDER.join(", ")}`);
      }
      lastTypeIdx = idx;
    }
  }

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const lineNum = i + 1;

    if (line.startsWith("<<<<<<<") || line.startsWith("=======") || 
        line.startsWith(">>>>>>>") || line.startsWith("|||||||")) {
      errors.push(`Line ${lineNum}: Unresolved conflict marker: "${line.slice(0, 40)}..."`);
    }

    if (line.match(/^## Unreleased/i)) {
      validateSection();
      hasUnreleasedSection = true;
      currentSection = "unreleased";
      sectionEntries = [];
      sectionStartLine = lineNum;
    } else if (line.match(/^## .+\(staging\)/i)) {
      validateSection();
      hasStagingSection = true;
      currentSection = "staging";
      sectionEntries = [];
      sectionStartLine = lineNum;
    } else if (line.match(/^## \d+\.\d+\.\d+/)) {
      validateSection();
      currentSection = "released";
      sectionEntries = [];
      sectionStartLine = lineNum;
    }

    if (currentSection != null && line.startsWith("- ")) {
      sectionEntries.push({ text: line, lineNum });
      const isActive = currentSection === "unreleased" || currentSection === "staging";
      if (isActive && !line.match(/^- (added|changed|fixed|deprecated|removed|security):/i)) {
        warnings.push(`Line ${lineNum}: Entry may not follow "- type: description" format`);
      }
    }

    if (line.match(/^-\s*$/)) {
      errors.push(`Line ${lineNum}: Empty list item found`);
    }
    if (line.match(/^--/) || line.match(/^- -/)) {
      errors.push(`Line ${lineNum}: Malformed list item`);
    }
  }
  validateSection();

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

  if (!skipInstall) {
    console.log("▶  yarn...");
    const installResult = runCommandWithLog("yarn", "yarn-install", repoDir);
    if (!installResult.success) {
      console.error(`✗  yarn - FAILED (log: ${installResult.logPath})\n`);
      return {
        success: false,
        failedStep: "yarn",
        logPath: installResult.logPath,
      };
    }
    console.log("✓  yarn - passed\n");
  } else {
    console.log("⏭  yarn - skipped (--skip-install)");
  }

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
      const eslintResult = runCommandWithLog(
        `npx eslint ${fileList}`,
        `eslint-${fileCount}-files`,
        repoDir
      );
      if (eslintResult.success) {
        console.log(`✓  eslint (changed files) - passed\n`);
        continue;
      }
      console.error(`✗  eslint (changed files) - FAILED (log: ${eslintResult.logPath})\n`);
      return {
        success: false,
        failedStep: "eslint (changed files)",
        logPath: eslintResult.logPath,
      };
    }

    console.log(`▶  yarn ${cmd}...`);
    const yarnResult = runCommandWithLog(`yarn ${cmd}`, `yarn-${cmd}`, repoDir);
    if (yarnResult.success) {
      console.log(`✓  yarn ${cmd} - passed\n`);
      continue;
    }
    console.error(`✗  yarn ${cmd} - FAILED (log: ${yarnResult.logPath})\n`);
    return {
      success: false,
      failedStep: `yarn ${cmd}`,
      logPath: yarnResult.logPath,
    };
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

if (requireChangelog && baseRef) {
  console.log("▶  CHANGELOG entry existence check...");
  try {
    const diff = execSync(`git diff --name-only ${baseRef}...HEAD -- CHANGELOG.md`, {
      cwd: repoDir, encoding: "utf8"
    }).trim();
    if (diff.length === 0) {
      console.error("✗  No CHANGELOG.md changes found but PR requires a changelog entry");
      console.error("\n=== Verification FAILED (CHANGELOG) ===");
      process.exit(2);
    }
    console.log("✓  CHANGELOG entry exists in diff");
  } catch (e) {
    console.error(`✗  Failed to check CHANGELOG diff: ${e.message}`);
    process.exit(2);
  }
}

const codeResult = verifyCode();
if (!codeResult.success) {
  console.error("\n=== Verification FAILED (Code) ===");
  console.error(`Failed step: ${codeResult.failedStep || codeResult.error}`);
  process.exit(1);
}

console.log("\n=== Verification PASSED ===");
process.exit(0);
