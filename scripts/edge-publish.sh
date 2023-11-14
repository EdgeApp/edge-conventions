#!/bin/bash

# Define colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
WHITEBG='\033[0;30;47m'
NC='\033[0m' # No Color

echo "---------------------------------------------"
echo "       Changelog & Version Bump Script       "
echo "             🚀 jon@edge.app 🚀               "
echo "---------------------------------------------"
echo ""

# Checkout master and reset to the tip
echo "Checking out latest master..."
git checkout master
git reset --hard origin/master

# Fetch the current version
current_version=$(node -e "
  const fs = require('fs');
  const package = JSON.parse(fs.readFileSync('package.json', 'utf8'));
  console.log(package.version);
")
echo -e "Current Version: $current_version\n"

# Parse the Unreleased section using Node.js
echo "Parsing Unreleased section:"
unreleased_changes=$(node -e "
  const fs = require('fs');
  const changelogPath = 'CHANGELOG.md';
  const changelogContent = fs.readFileSync(changelogPath, 'utf8');
  const unreleasedStart = changelogContent.indexOf('## Unreleased');
  // Check if the Unreleased section is found
  if (unreleasedStart === -1) {
    console.error('The "Unreleased" section is not present.');
    process.exit(1);
  }
  const nextVersionStart = changelogContent.indexOf('## ', unreleasedStart + '## Unreleased'.length);
  const unreleasedSection = changelogContent.substring(
    unreleasedStart + '## Unreleased'.length,
    nextVersionStart !== -1 ? nextVersionStart : undefined
  ).trim();

  // Trim and remove empty lines from the unreleased section
  const entries = unreleasedSection.split('\\n')
    .map(line => line.trim())
    .filter(line => line.length !== 0 && !line.startsWith('## '))
    .join('\\n');
  console.log(entries);
" || echo "")

# Validate if we have unreleased changes or if an early exit needs to happen
if [[ -z "$(echo "$unreleased_changes" | tr -d '[:space:]')" ]]; then
  echo "

❗❗ERROR❗❗ No contents found in the Unreleased section or the section is missing
"
  exit 1
fi

# Check each line of the commit messages for valid tags
allowed_tags=("- added:" "- changed:" "- deprecated:" "- removed:" "- fixed:" "- security:")
patch_only=true

IFS=$'\n'

for line in $unreleased_changes; do
    match=false
    for tag in "${allowed_tags[@]}"; do
        if [[ $line == $tag* ]]; then
            match=true
            
            if [[ $tag == "- added:" ]]; then
                echo -e "${GREEN}$line${NC}"
                patch_only=false
            elif [[ $tag == "- changed:" ]]; then
                echo -e "${YELLOW}$line${NC}"
                patch_only=false
            elif [[ $tag == "- fixed:" ]]; then
                echo -e "${RED}$line${NC}"
            else
                echo "${WHITEBG}$line${NC}"
            fi
        fi
    done

    if ! $match && [[ ! -z "$line" ]]; then
        echo -e "\n\n❗❗ERROR❗❗\nMessage doesn't start with a valid tag\n\n"
        exit 1
    fi
done

echo ""

# Determine new version number. Add to package.json and save new_version
new_version=$(node -e "
  const fs = require('fs');
  const package = JSON.parse(fs.readFileSync('package.json', 'utf8'));
  const versionParts = package.version.split('.');
  if ($patch_only) {
    versionParts[2] = String(parseInt(versionParts[2]) + 1);
  } else {
    versionParts[1] = String(parseInt(versionParts[1]) + 1);
    versionParts[2] = '0';
  }
  package.version = versionParts.join('.');
  fs.writeFileSync('package.json', JSON.stringify(package, null, 2));
  console.log(package.version);
")

if $patch_only; then
  echo -e "New Version: [${WHITEBG} $new_version ${NC}] ${RED}(PATCH RELEASE)${NC}"
else
  echo -e "New Version: [${WHITEBG} $new_version ${NC}]"
fi

# Modify the CHANGELOG file to add a new section under the Unreleased header with the new version and current date
node -e "
  const fs = require('fs');
  const newVersion = '$new_version';
  const newDate = '$(date +%Y-%m-%d)'; // Get current date in format YYYY-MM-DD
  const changelogPath = 'CHANGELOG.md';
  
  let changelog = fs.readFileSync(changelogPath, 'utf8');
  const unreleasedHeading = '## Unreleased';
  const newVersionHeading = \`## \${newVersion} (\${newDate})\`; // New heading for the changelog
  const newChangelog = changelog.replace(unreleasedHeading, unreleasedHeading + '\\n\\n' + newVersionHeading);
  
  fs.writeFileSync(changelogPath, newChangelog);
"

# Open the diffs for verification
# wait for file write
sleep 0.25 
git difftool -y HEAD~1 -- package.json &
git difftool -y HEAD~1 -- CHANGELOG.md &

# Commit changes
git add package.json CHANGELOG.md  > /dev/null 2>&1
git commit -m "v$new_version" --no-verify
git tag "v$new_version"  > /dev/null 2>&1

# Prepopulate commit message
echo "v$new_version" > .git/COMMIT_EDITMSG

# Push & publish
echo -e "
⚠️ ${YELLOW}Verify opened v$new_version changes!${NC} ⚠️

Do you want to push and npm publish?
Press 'Y' to proceed, any other key to revert. "
read -r -n 1 -p ""
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    git push origin master
    git push origin "v$new_version"
    npm publish
else
    echo "Reverting changes..."
    git tag -d "v$new_version" 2> /dev/null
    git reset --hard origin/master

    exit 1
fi

echo "---------------------------------------------"
echo "             🚀 Complete! 🚀                  "
echo "---------------------------------------------"
