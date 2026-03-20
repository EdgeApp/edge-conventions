#!/usr/bin/env bash
# tool-sync.sh — Sync Cursor rules, skills, and scripts to OpenCode and Claude Code.
# Source of truth: ~/.cursor/
# Targets: ~/.config/opencode/, ~/.claude/
#
# Usage: tool-sync.sh [--dry-run] [--target opencode|claude|all]
#   --dry-run   Show what would change without writing files
#   --target    Sync to a specific target (default: all)

set -euo pipefail

CURSOR_DIR="$HOME/.cursor"
OPENCODE_DIR="$HOME/.config/opencode"
CLAUDE_DIR="$HOME/.claude"
DRY_RUN=false
TARGET="all"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --target) TARGET="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Counters
created=0
updated=0
removed=0
skipped=0

log() { echo "  $1"; }
log_action() {
  local action="$1" file="$2"
  if [[ "$DRY_RUN" == true ]]; then
    echo "  [DRY-RUN] $action: $file"
  else
    echo "  $action: $file"
  fi
}

# ─── Helpers ──────────────────────────────────────────────────────────────────

# Convert .mdc to .md: strip Cursor-specific XML tags, keep content
mdc_to_md() {
  local src="$1"
  # .mdc files are already valid markdown with YAML frontmatter.
  # Some use <goal>, <rules>, <rule>, <step> XML tags — convert to markdown.
  sed \
    -e 's|^<goal>\(.*\)</goal>|## Goal\n\n\1|' \
    -e 's|^<goal>|## Goal\n|' \
    -e 's|^</goal>||' \
    -e 's|^<rules>|## Rules\n|' \
    -e 's|^</rules>||' \
    -e 's|^<rule id="\([^"]*\)">\(.*\)</rule>|- **\1**: \2|' \
    -e 's|^<rule id="\([^"]*\)">|- **\1**:|' \
    -e 's|^</rule>||' \
    -e 's|^<step id="\([^"]*\)" name="\([^"]*\)">|### Step \1: \2\n|' \
    -e 's|^</step>||' \
    -e '/^$/N;/^\n$/d' \
    "$src"
}

# Generate OpenCode JSON metadata from a .mdc rule file
generate_rule_json() {
  local src="$1" name="$2"
  local description="" always_apply="false" globs="[]"

  # Parse YAML frontmatter
  local in_frontmatter=false
  while IFS= read -r line; do
    if [[ "$line" == "---" ]]; then
      if [[ "$in_frontmatter" == true ]]; then break; fi
      in_frontmatter=true
      continue
    fi
    if [[ "$in_frontmatter" == true ]]; then
      case "$line" in
        description:*) description="${line#description: }" ;;
        alwaysApply:*) always_apply="${line#alwaysApply: }" ;;
        globs:*) globs="${line#globs: }" ;;
      esac
    fi
  done < "$src"

  jq -n \
    --arg id "$name" \
    --arg title "$name" \
    --arg description "$description" \
    --argjson globs "$globs" \
    --argjson alwaysApply "$always_apply" \
    '{id: $id, title: $title, description: $description, globs: $globs, alwaysApply: $alwaysApply}'
}

# Generate OpenCode JSON metadata from a command .md file
generate_command_json() {
  local src="$1" name="$2"

  # Extract goal line (first paragraph after ## Goal)
  local goal=""
  goal=$(awk '/^## Goal/{getline; getline; print; exit}' "$src")

  # Extract rules as JSON array
  local rules="[]"
  rules=$(awk '
    /^## Rules/,/^## |^### Step/ {
      if (/^- \*\*([^*]+)\*\*: (.+)/) {
        match($0, /\*\*([^*]+)\*\*: (.+)/, m)
        if (m[1] != "") {
          printf "{\"id\":\"%s\",\"instruction\":\"%s\"}\n", m[1], m[2]
        }
      }
    }
  ' "$src" | jq -s '.' 2>/dev/null || echo "[]")

  # Extract steps as JSON array
  local steps="[]"
  steps=$(awk '
    /^### Step [0-9]+:/ {
      match($0, /^### Step ([0-9]+): (.+)/, m)
      if (m[1] != "") {
        if (step_id != "") { printf "{\"id\":\"%s\",\"name\":\"%s\",\"instruction\":\"%s\"}\n", step_id, step_name, instruction }
        step_id = m[1]; step_name = m[2]; instruction = ""
      }
      next
    }
    /^## / { if (step_id != "") { printf "{\"id\":\"%s\",\"name\":\"%s\",\"instruction\":\"%s\"}\n", step_id, step_name, instruction; step_id="" } next }
    step_id != "" { gsub(/"/, "\\\""); instruction = instruction ($0 != "" ? (instruction != "" ? "\\n" : "") $0 : "") }
    END { if (step_id != "") printf "{\"id\":\"%s\",\"name\":\"%s\",\"instruction\":\"%s\"}\n", step_id, step_name, instruction }
  ' "$src" | jq -s '.' 2>/dev/null || echo "[]")

  jq -n \
    --arg id "$name" \
    --arg title "$name" \
    --arg description "$goal" \
    --arg goal "$goal" \
    --argjson rules "$rules" \
    --argjson steps "$steps" \
    '{id: $id, title: $title, description: $description, goal: $goal, rules: $rules, steps: $steps, scripts: ["sh"]}'
}

# Copy file only if changed, respecting --dry-run
sync_file() {
  local src="$1" dest="$2"
  if [[ ! -f "$dest" ]]; then
    log_action "CREATE" "$dest"
    if [[ "$DRY_RUN" == false ]]; then
      mkdir -p "$(dirname "$dest")"
      cp "$src" "$dest"
    fi
    ((created++)) || true
  elif ! diff -q "$src" "$dest" >/dev/null 2>&1; then
    log_action "UPDATE" "$dest"
    if [[ "$DRY_RUN" == false ]]; then
      cp "$src" "$dest"
    fi
    ((updated++)) || true
  else
    ((skipped++)) || true
  fi
}

# Write content to file only if changed
sync_content() {
  local content="$1" dest="$2"
  local tmp
  tmp=$(mktemp)
  cat <<< "$content" > "$tmp"
  if [[ ! -f "$dest" ]]; then
    log_action "CREATE" "$dest"
    if [[ "$DRY_RUN" == false ]]; then
      mkdir -p "$(dirname "$dest")"
      mv "$tmp" "$dest"
    else
      rm "$tmp"
    fi
    ((created++)) || true
  elif ! diff -q "$tmp" "$dest" >/dev/null 2>&1; then
    log_action "UPDATE" "$dest"
    if [[ "$DRY_RUN" == false ]]; then
      mv "$tmp" "$dest"
    else
      rm "$tmp"
    fi
    ((updated++)) || true
  else
    rm "$tmp"
    ((skipped++)) || true
  fi
}

# Create symlink, replacing if target changed
sync_symlink() {
  local src="$1" dest="$2"
  if [[ -L "$dest" ]]; then
    local current
    current=$(readlink "$dest")
    if [[ "$current" == "$src" ]]; then
      ((skipped++)) || true
      return
    fi
    log_action "UPDATE" "$dest -> $src"
    if [[ "$DRY_RUN" == false ]]; then
      ln -sf "$src" "$dest"
    fi
    ((updated++)) || true
  elif [[ -f "$dest" ]]; then
    log_action "REPLACE" "$dest (file -> symlink)"
    if [[ "$DRY_RUN" == false ]]; then
      rm "$dest"
      ln -s "$src" "$dest"
    fi
    ((updated++)) || true
  else
    log_action "CREATE" "$dest -> $src"
    if [[ "$DRY_RUN" == false ]]; then
      mkdir -p "$(dirname "$dest")"
      ln -s "$src" "$dest"
    fi
    ((created++)) || true
  fi
}

# ─── OpenCode Sync ────────────────────────────────────────────────────────────

sync_opencode() {
  echo "━━━ Syncing to OpenCode ━━━"

  # Rules: .mdc → .md + .json
  echo "  Rules:"
  for mdc in "$CURSOR_DIR"/rules/*.mdc; do
    [[ -f "$mdc" ]] || continue
    local name
    name=$(basename "$mdc" .mdc)

    # Convert .mdc to .md
    local tmp_md
    tmp_md=$(mktemp)
    mdc_to_md "$mdc" > "$tmp_md"
    sync_file "$tmp_md" "$OPENCODE_DIR/rules/$name.md"
    rm -f "$tmp_md"

    # Generate .json
    local json
    json=$(generate_rule_json "$mdc" "$name")
    sync_content "$json" "$OPENCODE_DIR/rules/$name.json"
  done

  # Skills: SKILL.md + scripts/ subdirs
  echo "  Skills:"
  if [[ -d "$CURSOR_DIR/skills" ]]; then
    # Shared scripts at skills/ top level
    for shared in "$CURSOR_DIR"/skills/*.sh; do
      [[ -f "$shared" ]] || continue
      local name
      name=$(basename "$shared")
      sync_file "$shared" "$OPENCODE_DIR/skills/$name"
    done
    # Skill dirs with SKILL.md + scripts/
    for skill_dir in "$CURSOR_DIR"/skills/*/; do
      [[ -d "$skill_dir" ]] || continue
      local name
      name=$(basename "$skill_dir")
      if [[ -f "$skill_dir/SKILL.md" ]]; then
        sync_file "$skill_dir/SKILL.md" "$OPENCODE_DIR/skills/$name/SKILL.md"
      fi
      if [[ -d "$skill_dir/scripts" ]]; then
        for script in "$skill_dir"/scripts/*; do
          [[ -f "$script" ]] || continue
          local fname
          fname=$(basename "$script")
          sync_file "$script" "$OPENCODE_DIR/skills/$name/scripts/$fname"
        done
      fi
    done
  fi

  # Standalone scripts
  echo "  Scripts:"
  for script in "$CURSOR_DIR"/scripts/*.sh "$CURSOR_DIR"/scripts/*.js; do
    [[ -f "$script" ]] || continue
    local name
    name=$(basename "$script")
    sync_file "$script" "$OPENCODE_DIR/scripts/$name"
  done

  # Clean up stale files in OpenCode that no longer exist in Cursor
  echo "  Cleanup:"
  for oc_rule in "$OPENCODE_DIR"/rules/*.md; do
    [[ -f "$oc_rule" ]] || continue
    local name
    name=$(basename "$oc_rule" .md)
    if [[ ! -f "$CURSOR_DIR/rules/$name.mdc" ]]; then
      log_action "REMOVE" "$oc_rule"
      if [[ "$DRY_RUN" == false ]]; then
        rm -f "$oc_rule" "$OPENCODE_DIR/rules/$name.json"
      fi
      ((removed++)) || true
    fi
  done

  for oc_skill_dir in "$OPENCODE_DIR"/skills/*/; do
    [[ -d "$oc_skill_dir" ]] || continue
    local name
    name=$(basename "$oc_skill_dir")
    if [[ ! -d "$CURSOR_DIR/skills/$name" ]]; then
      log_action "REMOVE" "$oc_skill_dir"
      if [[ "$DRY_RUN" == false ]]; then
        rm -rf "$oc_skill_dir"
      fi
      ((removed++)) || true
    fi
  done
}

# ─── Claude Code Sync ─────────────────────────────────────────────────────────

sync_claude() {
  echo "━━━ Syncing to Claude Code ━━━"

  # Skills: symlink SKILL.md files
  echo "  Skills (symlinks):"
  if [[ -d "$CURSOR_DIR/skills" ]]; then
    for skill_dir in "$CURSOR_DIR"/skills/*/; do
      [[ -d "$skill_dir" ]] || continue
      local name
      name=$(basename "$skill_dir")
      if [[ -f "$skill_dir/SKILL.md" ]]; then
        sync_symlink "$skill_dir/SKILL.md" "$CLAUDE_DIR/skills/$name/SKILL.md"
      fi
    done
  fi

  # Clean up stale symlinks
  if [[ -d "$CLAUDE_DIR/skills" ]]; then
    for link in "$CLAUDE_DIR"/skills/*/SKILL.md; do
      [[ -e "$link" ]] || continue
      if [[ -L "$link" ]]; then
        local target
        target=$(readlink "$link")
        if [[ ! -f "$target" ]]; then
          log_action "REMOVE" "$link (dead symlink)"
          if [[ "$DRY_RUN" == false ]]; then rm "$link"; fi
          ((removed++)) || true
        fi
      fi
    done
  fi

  # CLAUDE.md: generate with @import for each rule
  echo "  CLAUDE.md:"
  local dest="$CLAUDE_DIR/CLAUDE.md"
  local tmp
  tmp=$(mktemp)

  {
    echo "# Rules"
    echo ""
    echo "# Imported from ~/.cursor/rules/ — do not edit manually."
    echo "# Re-generate with: ~/.cursor/scripts/tool-sync.sh"
    echo ""
    for mdc in "$CURSOR_DIR"/rules/*.mdc; do
      [[ -f "$mdc" ]] || continue
      echo "@$mdc"
    done
  } > "$tmp"

  if [[ ! -f "$dest" ]]; then
    log_action "CREATE" "$dest"
    if [[ "$DRY_RUN" == false ]]; then
      mv "$tmp" "$dest"
    else
      rm "$tmp"
    fi
    ((created++)) || true
  elif ! diff -q "$tmp" "$dest" >/dev/null 2>&1; then
    log_action "UPDATE" "$dest"
    if [[ "$DRY_RUN" == false ]]; then
      mv "$tmp" "$dest"
    else
      rm "$tmp"
    fi
    ((updated++)) || true
  else
    rm "$tmp"
    ((skipped++)) || true
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────

echo "tool-sync: Cursor → ${TARGET}"
if [[ "$DRY_RUN" == true ]]; then
  echo "(dry run — no files will be modified)"
fi
echo ""

case "$TARGET" in
  opencode) sync_opencode ;;
  claude)   sync_claude ;;
  all)      sync_opencode; echo ""; sync_claude ;;
  *)        echo "Unknown target: $TARGET" >&2; exit 1 ;;
esac

echo ""
echo "Done: $created created, $updated updated, $removed removed, $skipped unchanged"
