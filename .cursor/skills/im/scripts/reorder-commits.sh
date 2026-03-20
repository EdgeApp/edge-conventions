#!/usr/bin/env bash
# reorder-commits.sh
# Reorder commits on a branch to a specified order using non-interactive rebase.
#
# Usage:
#   reorder-commits.sh <base-branch> <hash1> <hash2> ...
#
# Arguments:
#   base-branch  The branch/ref to rebase onto (e.g., origin/develop)
#   hash1..N     Commit hashes in desired order (oldest to newest)
#
# The script verifies all hashes exist in base..HEAD, writes an awk-based
# GIT_SEQUENCE_EDITOR to reorder the pick lines, and runs git rebase -i.
# It verifies the tree is unchanged after rebase.
#
# Exit codes:
#   0 - Reorder successful
#   1 - Reorder failed (conflict, missing commits, tree mismatch)
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "Usage: reorder-commits.sh <base-branch> <hash1> <hash2> ..." >&2
  exit 1
fi

BASE="$1"
shift
DESIRED_ORDER=("$@")

# Remove stale index locks
rm -f .git/index.lock

# Get short hashes for matching rebase todo lines
BRANCH_COMMITS=$(git log --reverse --format='%h' "$BASE..HEAD")
BRANCH_COUNT=$(echo "$BRANCH_COMMITS" | wc -l | tr -d ' ')
DESIRED_COUNT=${#DESIRED_ORDER[@]}

if [[ "$BRANCH_COUNT" -ne "$DESIRED_COUNT" ]]; then
  echo "Error: Branch has $BRANCH_COUNT commits but $DESIRED_COUNT hashes were provided" >&2
  echo "Branch commits: $BRANCH_COMMITS" >&2
  exit 1
fi

# Resolve desired hashes to short hashes and verify they're on the branch
DESIRED_SHORT=()
for hash in "${DESIRED_ORDER[@]}"; do
  short=$(git rev-parse --short "$hash" 2>/dev/null) || {
    echo "Error: Cannot resolve hash '$hash'" >&2
    exit 1
  }
  if ! echo "$BRANCH_COMMITS" | grep -q "^${short}$"; then
    echo "Error: Commit $short is not in $BASE..HEAD" >&2
    exit 1
  fi
  DESIRED_SHORT+=("$short")
done

# Capture pre-rebase tree for verification
PRE_TREE=$(git rev-parse HEAD^{tree})

# Build awk script that reorders pick lines to match desired order
# The awk program collects all pick lines, then outputs them in the order
# specified by the DESIRED env var (space-separated short hashes)
EDITOR_SCRIPT=$(mktemp)
trap 'rm -f "$EDITOR_SCRIPT"' EXIT

cat > "$EDITOR_SCRIPT" << 'AWKSCRIPT'
#!/usr/bin/env bash
exec awk -v desired="$DESIRED" '
BEGIN {
  n = split(desired, order, " ")
}
/^pick / {
  hash = $2
  lines[hash] = $0
  next
}
/^$/ || /^#/ { next }
END {
  for (i = 1; i <= n; i++) {
    for (h in lines) {
      if (index(h, order[i]) == 1 || index(order[i], h) == 1) {
        print lines[h]
        break
      }
    }
  }
}
' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
AWKSCRIPT
chmod +x "$EDITOR_SCRIPT"

export DESIRED="${DESIRED_SHORT[*]}"
if GIT_SEQUENCE_EDITOR="$EDITOR_SCRIPT" git rebase -i "$BASE" 2>/dev/null; then
  POST_TREE=$(git rev-parse HEAD^{tree})
  if [[ "$PRE_TREE" == "$POST_TREE" ]]; then
    echo ">> Commits reordered successfully"
    git log --oneline "$BASE..HEAD"
  else
    echo "Error: Tree changed after reorder (pre: $PRE_TREE, post: $POST_TREE)" >&2
    echo "This indicates content was lost or modified during rebase." >&2
    exit 1
  fi
else
  git rebase --abort 2>/dev/null || true
  echo "Error: Rebase failed (likely conflict). Aborted." >&2
  exit 1
fi
