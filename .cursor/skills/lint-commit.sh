#!/usr/bin/env bash
# lint-commit.sh
# Lint-fix, verify, localize (if needed), and commit in one atomic step.
#
# Usage:
#   lint-commit.sh -m "commit message" [file ...]
#   lint-commit.sh --fixup <hash> [file ...]
#   lint-commit.sh -m "fixup! Original commit" [file ...]   # Auto-reorders
#
# Options:
#   -m "msg"       Commit message (mutually exclusive with --fixup)
#   --fixup <hash> Create a fixup commit targeting <hash>
#   --reorder      After fixup commit, rebase to place it after its target (default: true)
#   --no-reorder   Skip the reorder rebase
#
# If files are given, they are the primary scope for linting/committing.
# The script may also auto-include generated companion files like:
#   - src/locales/strings
#   - eslint.config.mjs
#   - __snapshots__/*.snap
# Any additional non-generated files are reported before commit.
# If no files are given, all staged + unstaged + untracked changes are used.
# The script will:
#   1. Run eslint --fix on .ts/.tsx files
#   2. Run eslint --quiet to verify no remaining errors (exits 1 if any)
#   2b. Check for new warnings on changed lines (exits 1 if any)
#   3. Run yarn localize if the project has a localize script
#   4. git add -A && git commit --no-verify
#   5. Run yarn test --findRelatedTests -u on committed .ts/.tsx files
#   6. If snapshots changed, amend the commit to include them
#   7. If commit is a fixup (--fixup or -m "fixup! ..."), reorder via rebase
set -euo pipefail

MESSAGE=""
FIXUP=""
REORDER="true"  # Default to reordering fixups
FILES=()
PRIMARY_SCOPE_DECLARED="false"

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
    --reorder)
      REORDER="true"
      shift
      ;;
    --no-reorder)
      REORDER="false"
      shift
      ;;
    *)
      FILES+=("$1")
      shift
      ;;
  esac
done

if [[ ${#FILES[@]} -gt 0 ]]; then
  PRIMARY_SCOPE_DECLARED="true"
fi

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

# Step 4: Stage files and report effective commit scope
if [[ "$PRIMARY_SCOPE_DECLARED" == "true" ]]; then
  echo ">> git add (scoped) && git commit"
  git add -- "${FILES[@]}"
  # Stage generated companion files if they have changes
  for companion in eslint.config.mjs; do
    if [[ -f "$companion" ]] && ! git diff --quiet -- "$companion" 2>/dev/null; then
      git add -- "$companion"
    fi
  done
  # Stage locales/strings if yarn localize changed them (already git-added by
  # yarn localize in some repos, but ensure they're staged)
  if git diff --quiet --cached -- src/locales/strings 2>/dev/null; then
    git diff --quiet -- src/locales/strings 2>/dev/null || git add -- src/locales/strings/ 2>/dev/null || true
  fi
else
  echo ">> git add -A && git commit"
  git add -A
fi

# Graduate files from eslint warning-override list if the repo has the script
if node -e "process.exit(require('./package.json').scripts?.['update-eslint-warnings'] ? 0 : 1)" 2>/dev/null; then
  echo ">> update-eslint-warnings"
  npm run --silent update-eslint-warnings
fi

if [[ "$PRIMARY_SCOPE_DECLARED" == "true" ]]; then
  echo ">> commit scope report"
  node -e '
const { execSync } = require("child_process")

const requested = [...new Set(process.argv.slice(1))].sort()
const staged = execSync("git diff --cached --name-only --diff-filter=ACMRD", {
  encoding: "utf8"
})
  .split("\n")
  .map(line => line.trim())
  .filter(Boolean)
  .sort()

const requestedSet = new Set(requested)
const isGeneratedCompanion = file => {
  return (
    file === "eslint.config.mjs" ||
    file === "src/locales/strings" ||
    /(^|\/)__snapshots__\/.*\.snap$/.test(file)
  )
}

const requestedStaged = []
const generatedStaged = []
const extraStaged = []
for (const file of staged) {
  if (requestedSet.has(file)) {
    requestedStaged.push(file)
  } else if (isGeneratedCompanion(file)) {
    generatedStaged.push(file)
  } else {
    extraStaged.push(file)
  }
}

const missingRequested = requested.filter(file => !staged.includes(file))

const printGroup = (title, files) => {
  if (files.length === 0) return
  console.log(title)
  for (const file of files) console.log("- " + file)
}

printGroup("Primary scope staged:", requestedStaged)
printGroup("Auto-generated companion files staged:", generatedStaged)
printGroup("Additional non-generated files staged:", extraStaged)
printGroup("Requested files not staged:", missingRequested)

if (extraStaged.length > 0) {
  console.log("Proceeding with additional non-generated files by default.")
}
' -- "${FILES[@]}"
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
    if [[ "$PRIMARY_SCOPE_DECLARED" == "true" ]]; then
      echo ">> Auto-generated companion files staged:"
      echo "$SNAP_CHANGES"
    fi
    git add -- $SNAP_CHANGES
    git commit --amend --no-edit --no-verify
  else
    echo ">> No snapshot changes"
  fi
fi

# Step 7: Reorder fixup commits to be adjacent to their targets
# Detects fixup commits by --fixup flag or "fixup! " prefix in message
IS_FIXUP="false"
if [[ -n "$FIXUP" ]]; then
  IS_FIXUP="true"
elif [[ "$MESSAGE" == fixup!* ]]; then
  IS_FIXUP="true"
fi

if [[ "$IS_FIXUP" == "true" && "$REORDER" == "true" ]]; then
  echo ">> Reordering fixup commit..."
  
  # Find the merge-base with the default upstream branch
  DEFAULT_UPSTREAM=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null \
    || echo "origin/$(git remote show origin 2>/dev/null | sed -n '/HEAD branch/s/.*: //p')" \
    || echo "origin/master")
  
  BASE=$(git merge-base "$DEFAULT_UPSTREAM" HEAD 2>/dev/null || echo "")
  
  if [[ -n "$BASE" ]]; then
    # Interactive rebase with autosquash to reorder (editor does nothing, so commits aren't squashed)
    if GIT_EDITOR=true git -c sequence.editor=: rebase -i "$BASE" --autosquash 2>/dev/null; then
      echo ">> Fixup reordered successfully"
    else
      # Rebase failed (likely conflict) - abort and warn
      git rebase --abort 2>/dev/null || true
      echo ">> Warning: Could not reorder fixup (conflict). Fixup remains at HEAD." >&2
      echo ">> Run 'git rebase -i --autosquash $BASE' manually to reorder." >&2
    fi
  else
    echo ">> Warning: Could not determine merge-base for reorder" >&2
  fi
fi

echo ">> Done"
