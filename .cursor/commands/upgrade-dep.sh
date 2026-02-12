#!/usr/bin/env bash
set -euo pipefail

# Standalone replacement for the upgrade_dep shell function.
# Usage: upgrade-dep.sh <package> [version]
#
# Stashes working changes, upgrades a dependency in package.json,
# runs yarn + prepare, commits the result, then pops the stash.

usage() {
    echo "Usage: upgrade-dep.sh <package> [version]"
    exit 1
}

package=""
new_version=""

case "$#" in
    1)
        package="$1"
        ;;
    2)
        package="$1"
        new_version="$2"
        ;;
    *)
        usage
        ;;
esac

# Stash any working changes
git stage .
git stash

# Resolve latest version from npm if none provided
if [ -z "$new_version" ]; then
    latest_version=$(npm view "$package" versions --json | jq -r '.[]' | sort -V | tail -n 1)
    new_version="^$latest_version"
fi

# Check if already at target version
current_version=$(jq -r ".dependencies[\"$package\"] // .devDependencies[\"$package\"]" package.json)
if [ "$current_version" = "$new_version" ]; then
    echo "Error: $package is already at version $new_version"
    git stash pop
    exit 1
fi

# Update package.json
sed -i "" "s#\"$package\": \".*\"#\"$package\": \"$new_version\"#" package.json

# Install and prepare
yarn && yarn prepare && yarn prepare.ios

# Remove git+ prefixes from yarn.lock
sed -i "" "s/git+//" yarn.lock

# Stage and commit
git add -A
git commit -m "Upgrade $package@$new_version" --no-verify
