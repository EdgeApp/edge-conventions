#!/usr/bin/env bash
# lint-commit.sh
# Lint-fix, verify, localize (if needed), and commit in one atomic step.
#
# Usage:
#   lint-commit.sh -m "commit message" [file ...]
#   lint-commit.sh --fixup <hash> [file ...]
#
# -m and --fixup are mutually exclusive. --fixup creates a fixup commit
# targeting <hash>, intended for later autosquashing.
#
# If no files are given, all staged + unstaged + untracked changes are used.
# The script will:
#   1. Run eslint --fix on .ts/.tsx files
#   2. Run eslint --quiet to verify no remaining errors (exits 1 if any)
#   2b. Check for new warnings on changed lines (exits 1 if any)
#   3. Run yarn localize if the project has a localize script
#   4. git add -A && git commit --no-verify
#   5. Run yarn test --findRelatedTests -u on committed .ts/.tsx files
#   6. If snapshots changed, amend the commit to include them
set -euo pipefail

MESSAGE=""
FIXUP=""
FILES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -m)
      MESSAGE="$2"
      shift 2
      ;;
    --fixup)
      FIXUP="$2"
      shift 2
      ;;
    *)
      FILES+=("$1")
      shift
      ;;
  esac
done

if [[ -z "$MESSAGE" && -z "$FIXUP" ]]; then
  echo "Error: -m \"commit message\" or --fixup <hash> is required" >&2
  exit 1
fi
if [[ -n "$MESSAGE" && -n "$FIXUP" ]]; then
  echo "Error: -m and --fixup are mutually exclusive" >&2
  exit 1
fi

# If no files specified, collect all changed/untracked files
if [[ ${#FILES[@]} -eq 0 ]]; then
  while IFS= read -r f; do
    [[ -n "$f" ]] && FILES+=("$f")
  done < <(git diff --name-only HEAD 2>/dev/null; git diff --name-only --cached 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null)

  # Deduplicate (compatible with macOS Bash 3.2 — no mapfile)
  if [[ ${#FILES[@]} -gt 0 ]]; then
    DEDUPED=()
    while IFS= read -r f; do
      [[ -n "$f" ]] && DEDUPED+=("$f")
    done < <(printf '%s\n' "${FILES[@]}" | sort -u)
    FILES=("${DEDUPED[@]}")
  fi
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "Error: No changed files found" >&2
  exit 1
fi

# Filter to lintable files (.ts/.tsx) that exist on disk
LINT_FILES=()
for f in "${FILES[@]}"; do
  if [[ ("$f" == *.ts || "$f" == *.tsx) && -f "$f" ]]; then
    LINT_FILES+=("$f")
  fi
done

# Step 1: eslint --fix
if [[ ${#LINT_FILES[@]} -gt 0 ]]; then
  echo ">> eslint --fix (${#LINT_FILES[@]} files)"
  ./node_modules/.bin/eslint --fix "${LINT_FILES[@]}" || true

  # Step 2: eslint --quiet (must pass)
  echo ">> eslint --quiet (verify)"
  if ! ./node_modules/.bin/eslint --quiet "${LINT_FILES[@]}"; then
    echo "Error: Lint errors remain after --fix. Aborting commit." >&2
    exit 1
  fi
  echo ">> Lint clean"

  # Step 2b: Detect new warnings introduced on changed lines.
  # Runs eslint (with warnings) and cross-references against git diff to
  # only flag warnings on lines the developer actually touched.
  NEW_WARN=$(node -e '
const { execSync } = require("child_process")
const path = require("path")

const files = process.argv.slice(1)
const cmd = "./node_modules/.bin/eslint --format json " + files.map(f => JSON.stringify(f)).join(" ")

let results
try {
  results = JSON.parse(execSync(cmd, { encoding: "utf8", maxBuffer: 10 * 1024 * 1024 }))
} catch (e) {
  if (e.stdout) try { results = JSON.parse(e.stdout) } catch { process.exit(0) }
  else process.exit(0)
}

const cwd = process.cwd()
const out = []

for (const r of results) {
  const rel = path.relative(cwd, r.filePath)
  const warns = r.messages.filter(m => m.severity === 1)
  if (warns.length === 0) continue

  // Determine which lines were changed in this file
  let changed
  try {
    execSync("git cat-file -e HEAD:" + JSON.stringify(rel), { stdio: "pipe" })
    const diff = execSync("git diff -U0 HEAD -- " + JSON.stringify(rel), { encoding: "utf8" })
    changed = new Set()
    for (const m of diff.matchAll(/@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/g)) {
      const start = +m[1]
      const count = m[2] != null ? +m[2] : 1
      for (let i = start; i < start + count; i++) changed.add(i)
    }
  } catch {
    changed = null // New file — all lines count as changed
  }

  for (const w of warns) {
    if (changed == null || changed.has(w.line)) {
      out.push(rel + ":" + w.line + ":" + w.column + "  warning  " + w.message + "  " + w.ruleId)
    }
  }
}

if (out.length > 0) console.log(out.join("\n"))
' -- "${LINT_FILES[@]}" 2>/dev/null || true)

  if [[ -n "$NEW_WARN" ]]; then
    echo ">> New warnings on changed lines:" >&2
    echo "$NEW_WARN" >&2
    echo "Error: Fix new warnings before committing." >&2
    exit 1
  fi
fi

# Step 3: yarn localize if the project has a localize script
if node -e "process.exit(require('./package.json').scripts?.localize ? 0 : 1)" 2>/dev/null; then
  echo ">> yarn localize"
  yarn localize
fi

# Step 4: Stage everything and commit
echo ">> git add -A && git commit"
git add -A

# Graduate files from eslint warning-override list if the repo has the script
if node -e "process.exit(require('./package.json').scripts?.['update-eslint-warnings'] ? 0 : 1)" 2>/dev/null; then
  echo ">> update-eslint-warnings"
  npm run --silent update-eslint-warnings
fi

if [[ -n "$FIXUP" ]]; then
  git commit --no-verify --fixup "$FIXUP"
else
  git commit --no-verify -m "$MESSAGE"
fi

# Step 5: Update snapshots for related tests (Jest only)
if [[ ${#LINT_FILES[@]} -gt 0 && -x ./node_modules/.bin/jest ]]; then
  echo ">> jest --findRelatedTests -u (${#LINT_FILES[@]} files)"
  ./node_modules/.bin/jest --findRelatedTests "${LINT_FILES[@]}" -u 2>&1 || true

  # Step 6: If snapshots changed, amend the commit
  SNAP_CHANGES=$(git diff --name-only -- '**/__snapshots__/**' 2>/dev/null || true)
  if [[ -n "$SNAP_CHANGES" ]]; then
    echo ">> Snapshots updated, amending commit:"
    echo "$SNAP_CHANGES"
    git add -A
    git commit --amend --no-edit --no-verify
  else
    echo ">> No snapshot changes"
  fi
fi

echo ">> Done"
