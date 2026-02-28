#!/usr/bin/env bash
# generate-claude-md.sh — Generate ~/.claude/CLAUDE.md from alwaysApply .mdc rules.
# Usage: ./generate-claude-md.sh [--dry-run]
#
# Reads all .mdc files in ~/.cursor/rules/ that have alwaysApply: true,
# strips YAML frontmatter, and concatenates them into ~/.claude/CLAUDE.md.

set -euo pipefail

RULES_DIR="$HOME/.cursor/rules"
OUTPUT="$HOME/.claude/CLAUDE.md"
DRY_RUN=false

[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

if [[ ! -d "$RULES_DIR" ]]; then
  echo "ERROR: $RULES_DIR does not exist" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT")"

collected=()
skipped=()

for mdc in "$RULES_DIR"/*.mdc; do
  [[ -f "$mdc" ]] || continue
  basename="$(basename "$mdc")"

  if head -20 "$mdc" | grep -q '^alwaysApply: true'; then
    collected+=("$basename")
  else
    skipped+=("$basename")
  fi
done

if [[ ${#collected[@]} -eq 0 ]]; then
  echo '{"collected":[],"skipped":[],"output":"","dry_run":true}'
  exit 0
fi

content="# Global Rules\n\n"
content+="# Auto-generated from ~/.cursor/rules/ (alwaysApply: true files only).\n"
content+="# Do not edit manually. Re-generate via convention-sync.\n\n"

for basename in "${collected[@]}"; do
  mdc="$RULES_DIR/$basename"
  name="${basename%.mdc}"

  # Strip YAML frontmatter (everything between first --- and second ---)
  body=$(awk '
    BEGIN { in_front=0; past_front=0 }
    /^---$/ {
      if (!past_front) {
        if (in_front) { past_front=1; next }
        else { in_front=1; next }
      }
    }
    past_front { print }
  ' "$mdc")

  # Trim leading blank lines
  body=$(echo "$body" | sed '/./,$!d')

  content+="---\n\n"
  content+="## $name\n\n"
  content+="$body\n\n"
done

if [[ "$DRY_RUN" == true ]]; then
  echo -e "$content" > /dev/null
else
  echo -e "$content" > "$OUTPUT"
fi

# Output JSON summary
collected_json=$(printf '%s\n' "${collected[@]}" | jq -R . | jq -s .)
skipped_json=$(printf '%s\n' "${skipped[@]}" | jq -R . | jq -s .)

jq -n \
  --argjson collected "$collected_json" \
  --argjson skipped "$skipped_json" \
  --arg output "$OUTPUT" \
  --arg dry_run "$DRY_RUN" \
  '{collected: $collected, skipped: $skipped, output: $output, dry_run: ($dry_run == "true")}'
