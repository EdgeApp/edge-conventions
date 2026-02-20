#!/usr/bin/env bash
# lint-warnings.sh
# Run eslint on files and match warnings to documented fix patterns.
#
# Usage:
#   lint-warnings.sh <file1> [file2] ...
#
# Output:
#   1. Summary of warnings per file/rule
#   2. Matched patterns from typescript-standards.mdc (full XML blocks)
#   3. Unmatched rules (need new patterns added)
#
# Exit codes:
#   0 - No warnings
#   1 - Warnings found (with or without matching patterns)
#   2 - Error (missing files, eslint failure, etc.)
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

# Run eslint with JSON output, pipe to node for processing
./node_modules/.bin/eslint --format json "${FILES[@]}" 2>/dev/null | node -e '
const fs = require("fs");
const path = require("path");

const patternsFile = process.argv[1];

let input = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", chunk => { input += chunk; });
process.stdin.on("end", () => {
  let results;
  try {
    results = JSON.parse(input);
  } catch (e) {
    console.error("Failed to parse eslint output");
    process.exit(2);
  }

  // Collect all warnings
  const warningsByRule = new Map();
  const warningsByFile = new Map();
  let totalWarnings = 0;

  for (const file of results) {
    const rel = path.relative(process.cwd(), file.filePath);
    const warnings = file.messages.filter(m => m.severity === 1);
    
    if (warnings.length > 0) {
      warningsByFile.set(rel, warnings);
      totalWarnings += warnings.length;
      
      for (const w of warnings) {
        const rule = w.ruleId || "unknown";
        if (!warningsByRule.has(rule)) {
          warningsByRule.set(rule, []);
        }
        warningsByRule.get(rule).push({ file: rel, line: w.line, message: w.message });
      }
    }
  }

  if (totalWarnings === 0) {
    console.log(">> No warnings found");
    process.exit(0);
  }

  // Read patterns file and extract <pattern> blocks with rule attributes
  let patternsContent = "";
  try {
    patternsContent = fs.readFileSync(patternsFile, "utf8");
  } catch (e) {
    console.error("Warning: Could not read patterns file:", patternsFile);
  }

  // Extract patterns with their rule attributes
  const patternRegex = /<pattern\s+id="([^"]+)"\s+rule="([^"]+)">([\s\S]*?)<\/pattern>/g;
  const patterns = new Map(); // rule -> [{ id, content }]

  let match;
  while ((match = patternRegex.exec(patternsContent)) !== null) {
    const [fullMatch, id, rule, content] = match;
    if (!patterns.has(rule)) {
      patterns.set(rule, []);
    }
    patterns.get(rule).push({ id, fullMatch });
  }

  // Output summary
  console.log(`>> ${totalWarnings} warning(s) in ${warningsByFile.size} file(s)\n`);

  console.log("=== Warnings by Rule ===");
  for (const [rule, instances] of [...warningsByRule.entries()].sort((a, b) => b[1].length - a[1].length)) {
    console.log(`\n${rule} (${instances.length}x):`);
    // Show up to 3 examples
    for (const inst of instances.slice(0, 3)) {
      console.log(`  ${inst.file}:${inst.line} - ${inst.message}`);
    }
    if (instances.length > 3) {
      console.log(`  ... and ${instances.length - 3} more`);
    }
  }

  // Match rules to patterns
  const matchedRules = [];
  const unmatchedRules = [];

  for (const rule of warningsByRule.keys()) {
    if (patterns.has(rule)) {
      matchedRules.push(rule);
    } else {
      unmatchedRules.push(rule);
    }
  }

  // Output matched patterns
  if (matchedRules.length > 0) {
    console.log("\n\n=== Matched Fix Patterns ===");
    for (const rule of matchedRules) {
      for (const p of patterns.get(rule)) {
        console.log(`\n${p.fullMatch}`);
      }
    }
  }

  // Output unmatched rules
  if (unmatchedRules.length > 0) {
    console.log("\n\n=== Unmatched Rules (need patterns added) ===");
    for (const rule of unmatchedRules) {
      console.log(`- ${rule}`);
    }
    console.log("\nAfter fixing these, add patterns to ~/.cursor/rules/typescript-standards.mdc");
  }

  process.exit(1);
});
' -- "$PATTERNS_FILE" || exit $?
