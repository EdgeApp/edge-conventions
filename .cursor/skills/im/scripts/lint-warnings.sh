#!/usr/bin/env bash
# lint-warnings.sh
# Run eslint --fix on files and match any remaining findings to documented fix
# patterns.
#
# Usage:
#   lint-warnings.sh <file1> [file2] ...
#
# Output:
#   1. Summary of auto-fixes applied (if any)
#   2. Summary of remaining findings per rule/severity
#   3. Matched patterns from typescript-standards.mdc (full XML blocks)
#   4. Unmatched rules (need new patterns added)
#
# Exit codes:
#   0 - No remaining lint findings after auto-fix
#   1 - Remaining lint findings after auto-fix
#   2 - Error (missing files, eslint runtime/config failure, etc.)
set -euo pipefail

PATTERNS_FILE="$HOME/.cursor/rules/typescript-standards.mdc"

if [[ $# -eq 0 ]]; then
  echo "Usage: lint-warnings.sh <file1> [file2] ..." >&2
  exit 2
fi

# Filter to existing .ts/.tsx files
FILES=()
for f in "$@"; do
  if [[ ("$f" == *.ts || "$f" == *.tsx) && -f "$f" ]]; then
    FILES+=("$f")
  fi
done

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "No .ts/.tsx files found" >&2
  exit 2
fi

# Run eslint with --fix, then classify any remaining lint findings.
TMP_JSON="$(mktemp)"
TMP_ERR="$(mktemp)"
trap 'rm -f "$TMP_JSON" "$TMP_ERR"' EXIT

set +e
./node_modules/.bin/eslint --fix --format json "${FILES[@]}" >"$TMP_JSON" 2>"$TMP_ERR"
ESLINT_EXIT=$?
set -e

node -e '
const fs = require("fs");
const path = require("path");

const patternsFile = process.argv[1];
const jsonFile = process.argv[2];
const errFile = process.argv[3];
const eslintExit = Number(process.argv[4]);

let input = "";
let stderrText = "";
try {
  input = fs.readFileSync(jsonFile, "utf8");
} catch (error) {
  console.error("Failed to read eslint JSON output");
  process.exit(2);
}

try {
  stderrText = fs.readFileSync(errFile, "utf8").trim();
} catch (error) {
  stderrText = "";
}

if (input.trim() === "") {
  if (stderrText !== "") console.error(stderrText);
  console.error("ESLint produced no JSON output");
  process.exit(2);
}

let results;
try {
  results = JSON.parse(input);
} catch (error) {
  if (stderrText !== "") console.error(stderrText);
  console.error("Failed to parse eslint output");
  process.exit(2);
}

if (!Array.isArray(results)) {
  console.error("Unexpected eslint JSON format");
  process.exit(2);
}

const findingsBySeverity = new Map([
  [2, new Map()],
  [1, new Map()]
]);
let totalErrors = 0;
let totalWarnings = 0;
let autoFixedFiles = 0;

for (const file of results) {
  if (file != null && typeof file.output === "string") autoFixedFiles += 1;

  const rel = path.relative(process.cwd(), file.filePath);
  for (const message of file.messages) {
    if (message.severity !== 1 && message.severity !== 2) continue;

    const findingsForSeverity = findingsBySeverity.get(message.severity);
    const rule = message.ruleId || "unknown";
    if (!findingsForSeverity.has(rule)) {
      findingsForSeverity.set(rule, []);
    }
    findingsForSeverity.get(rule).push({
      file: rel,
      line: message.line,
      message: message.message
    });

    if (message.severity === 2) totalErrors += 1;
    if (message.severity === 1) totalWarnings += 1;
  }
}

if (eslintExit > 1 && totalErrors === 0 && totalWarnings === 0) {
  if (stderrText !== "") console.error(stderrText);
  console.error("ESLint failed before reporting lint findings");
  process.exit(2);
}

if (autoFixedFiles > 0) {
  console.log(`>> Auto-fixed ${autoFixedFiles} file(s)`);
}

if (totalErrors === 0 && totalWarnings === 0) {
  console.log(">> No remaining lint findings");
  process.exit(0);
}

let patternsContent = "";
try {
  patternsContent = fs.readFileSync(patternsFile, "utf8");
} catch (error) {
  console.error("Warning: Could not read patterns file:", patternsFile);
}

const patternRegex = /<pattern\s+id="([^"]+)"\s+rule="([^"]+)">([\s\S]*?)<\/pattern>/g;
const patterns = new Map();
let match;
while ((match = patternRegex.exec(patternsContent)) !== null) {
  const [fullMatch, id, rule] = match;
  if (!patterns.has(rule)) {
    patterns.set(rule, []);
  }
  patterns.get(rule).push({ id, fullMatch });
}

if (totalErrors > 0) {
  console.log(`>> ${totalErrors} remaining error(s)`);
}
if (totalWarnings > 0) {
  console.log(`>> ${totalWarnings} remaining warning(s)`);
}

const printFindings = (heading, findingsByRule) => {
  if (findingsByRule.size === 0) return;

  console.log(`\n=== ${heading} ===`);
  for (const [rule, instances] of [...findingsByRule.entries()].sort((left, right) => right[1].length - left[1].length)) {
    console.log(`\n${rule} (${instances.length}x):`);
    for (const inst of instances.slice(0, 3)) {
      console.log(`  ${inst.file}:${inst.line} - ${inst.message}`);
    }
    if (instances.length > 3) {
      console.log(`  ... and ${instances.length - 3} more`);
    }
  }
};

printFindings("Remaining Errors by Rule", findingsBySeverity.get(2));
printFindings("Remaining Warnings by Rule", findingsBySeverity.get(1));

const matchedRules = [];
const unmatchedRules = [];
const seenRules = new Set();
for (const findingsByRule of findingsBySeverity.values()) {
  for (const rule of findingsByRule.keys()) {
    if (seenRules.has(rule)) continue;
    seenRules.add(rule);
    if (patterns.has(rule)) {
      matchedRules.push(rule);
    } else {
      unmatchedRules.push(rule);
    }
  }
}

if (matchedRules.length > 0) {
  console.log("\n\n=== Matched Fix Patterns ===");
  for (const rule of matchedRules) {
    for (const pattern of patterns.get(rule)) {
      console.log(`\n${pattern.fullMatch}`);
    }
  }
}

if (unmatchedRules.length > 0) {
  console.log("\n\n=== Unmatched Rules (need patterns added) ===");
  for (const rule of unmatchedRules) {
    console.log(`- ${rule}`);
  }
  console.log("\nAfter fixing these, add patterns to ~/.cursor/rules/typescript-standards.mdc");
}

process.exit(1);
' -- "$PATTERNS_FILE" "$TMP_JSON" "$TMP_ERR" "$ESLINT_EXIT"
