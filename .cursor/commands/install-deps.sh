#!/usr/bin/env bash
set -euo pipefail

# install-deps.sh — Install dependencies and run prepare script.
# Usage: install-deps.sh [repo-dir]
#
# Runs `yarn install` and `yarn prepare` (if prepare script exists in package.json).
# Use after: branch creation, rebase onto upstream, checkout.
#
# Exit codes:
#   0 = Success (or no package.json — skipped)
#   1 = Install or prepare failed

repo_dir="${1:-.}"

if [ ! -f "$repo_dir/package.json" ]; then
  echo "⏭  No package.json — skipping dependency install" >&2
  exit 0
fi

echo "Installing dependencies..." >&2
(cd "$repo_dir" && yarn install)

if (cd "$repo_dir" && node -e "process.exit(require('./package.json').scripts?.prepare ? 0 : 1)" 2>/dev/null); then
  echo "Running prepare..." >&2
  (cd "$repo_dir" && yarn prepare)
fi

echo "✓ Dependencies installed and prepared" >&2
