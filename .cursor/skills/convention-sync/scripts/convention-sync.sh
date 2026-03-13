#!/usr/bin/env bash
# convention-sync.sh — Sync ~/.cursor/ files with the edge-conventions repo.
# Usage: ./convention-sync.sh [repo-dir] [--stage] [--commit -m "message"] [--repo-to-user]
# Compares ~/.cursor/{skills,rules,scripts} against <repo-dir>/.cursor/ and
# outputs a structured JSON summary of new, modified, and deleted files.
# With --stage: copies changed files and stages them in git (or copies to user dir with --repo-to-user).
# With --commit: stages + commits (requires -m). Only valid for user-to-repo direction.
#
# Sync model: ~/.cursor/ is canonical. Default direction (user-to-repo) copies local
# files into the repo. --repo-to-user is for onboarding or pulling others' changes.
# No bidirectional conflict detection — the chosen direction overwrites the other side.

set -euo pipefail

REPO_DIR=""
DO_STAGE=false
DO_COMMIT=false
COMMIT_MSG=""
DIRECTION="user-to-repo"

resolve_default_repo_dir() {
  local cwd remote_url default_repo

  cwd="$(pwd)"
  if [[ "$(basename "$cwd")" == "edge-conventions" ]]; then
    printf '%s\n' "$cwd"
    return 0
  fi

  if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    remote_url="$(git -C "$cwd" remote get-url origin 2>/dev/null || true)"
    if [[ "$remote_url" == *"edge-conventions"* ]]; then
      printf '%s\n' "$cwd"
      return 0
    fi
  fi

  default_repo="$HOME/git/edge-conventions"
  if [[ -d "$default_repo/.git" || -f "$default_repo/.git" ]]; then
    printf '%s\n' "$default_repo"
    return 0
  fi

  return 1
}

validate_repo_dir() {
  local repo_dir remote_url
  repo_dir="$1"

  if [[ ! -d "$repo_dir/.cursor" ]]; then
    echo "ERROR: Repo directory must contain .cursor/: $repo_dir" >&2
    return 1
  fi

  if [[ "$(basename "$repo_dir")" == "edge-conventions" ]]; then
    return 0
  fi

  if git -C "$repo_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    remote_url="$(git -C "$repo_dir" remote get-url origin 2>/dev/null || true)"
    if [[ "$remote_url" == *"edge-conventions"* ]]; then
      return 0
    fi
  fi

  echo "ERROR: Repo directory does not appear to be the edge-conventions checkout: $repo_dir" >&2
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stage) DO_STAGE=true; shift ;;
    --commit) DO_COMMIT=true; DO_STAGE=true; shift ;;
    -m) COMMIT_MSG="$2"; shift 2 ;;
    --repo-to-user) DIRECTION="repo-to-user"; shift ;;
    *) REPO_DIR="$1"; shift ;;
  esac
done

if [[ -z "$REPO_DIR" ]]; then
  if ! REPO_DIR="$(resolve_default_repo_dir)"; then
    echo "ERROR: Could not resolve the edge-conventions repo. Run with an explicit repo path." >&2
    echo "Usage: convention-sync.sh [repo-dir] [--stage] [--commit -m \"message\"]" >&2
    exit 1
  fi
fi

if ! validate_repo_dir "$REPO_DIR"; then
  exit 1
fi

if [[ "$DO_COMMIT" == true && -z "$COMMIT_MSG" ]]; then
  echo "ERROR: --commit requires -m \"message\"" >&2
  exit 1
fi

USER_DIR="$HOME/.cursor"
REPO_CURSOR="$REPO_DIR/.cursor"
DIRS="skills rules scripts"
SYNCIGNORE="$USER_DIR/.syncignore"

# Load ignore patterns from .syncignore (one glob per line, # comments, blank lines skipped)
ignore_patterns=()
if [[ -f "$SYNCIGNORE" ]]; then
  while IFS= read -r line; do
    line="${line%%#*}"       # strip comments
    line="${line%"${line##*[![:space:]]}"}"  # strip trailing whitespace
    [[ -z "$line" ]] && continue
    ignore_patterns+=("$line")
  done < "$SYNCIGNORE"
fi

is_ignored() {
  local entry="$1"
  for pattern in "${ignore_patterns[@]+"${ignore_patterns[@]}"}"; do
    # shellcheck disable=SC2254
    if [[ "$entry" == $pattern ]]; then
      return 0
    fi
  done
  return 1
}

new_json="[]"
mod_json="[]"
del_json="[]"
ignored_json="[]"

# Check README.md separately (single file, not a directory)
if [[ -f "$USER_DIR/README.md" ]] && ! is_ignored "README.md"; then
  if [[ ! -f "$REPO_CURSOR/README.md" ]]; then
    new_json=$(echo "$new_json" | jq '. + ["README.md"]')
  elif ! diff -q "$USER_DIR/README.md" "$REPO_CURSOR/README.md" >/dev/null 2>&1; then
    mod_json=$(echo "$mod_json" | jq '. + ["README.md"]')
  fi
elif [[ -f "$REPO_CURSOR/README.md" ]] && ! is_ignored "README.md"; then
  del_json=$(echo "$del_json" | jq '. + ["README.md"]')
fi

for dir in $DIRS; do
  user_path="$USER_DIR/$dir"
  repo_path="$REPO_CURSOR/$dir"

  [[ -d "$user_path" ]] || continue

  while IFS= read -r rel; do
    [[ -z "$rel" ]] && continue
    entry="$dir/$rel"
    if is_ignored "$entry"; then
      ignored_json=$(echo "$ignored_json" | jq --arg f "$entry" '. + [$f]')
      continue
    fi
    repo_file="$repo_path/$rel"
    if [[ ! -f "$repo_file" ]]; then
      new_json=$(echo "$new_json" | jq --arg f "$entry" '. + [$f]')
    elif ! diff -q "$user_path/$rel" "$repo_file" >/dev/null 2>&1; then
      mod_json=$(echo "$mod_json" | jq --arg f "$entry" '. + [$f]')
    fi
  done < <(cd "$user_path" && find . -type f ! -name '.DS_Store' | sed 's|^\./||')

  if [[ -d "$repo_path" ]]; then
    while IFS= read -r rel; do
      [[ -z "$rel" ]] && continue
      entry="$dir/$rel"
      is_ignored "$entry" && continue
      user_file="$user_path/$rel"
      if [[ ! -f "$user_file" ]]; then
        del_json=$(echo "$del_json" | jq --arg f "$entry" '. + [$f]')
      fi
    done < <(cd "$repo_path" && find . -type f ! -name '.DS_Store' | sed 's|^\./||')
  fi
done

total=$(echo "$new_json $mod_json $del_json" | jq -s '.[0] + .[1] + .[2] | length')

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure ~/.claude/skills symlink points to ~/.cursor/skills
CLAUDE_SKILLS="$HOME/.claude/skills"
if [[ -L "$CLAUDE_SKILLS" ]]; then
  link_target="$(readlink "$CLAUDE_SKILLS")"
  if [[ "$link_target" != "$USER_DIR/skills" ]]; then
    rm "$CLAUDE_SKILLS"
    ln -s "$USER_DIR/skills" "$CLAUDE_SKILLS"
  fi
elif [[ ! -e "$CLAUDE_SKILLS" ]]; then
  mkdir -p "$(dirname "$CLAUDE_SKILLS")"
  ln -s "$USER_DIR/skills" "$CLAUDE_SKILLS"
fi

# Regenerate ~/.claude/CLAUDE.md from alwaysApply rules
if [[ -x "$SCRIPT_DIR/generate-claude-md.sh" ]]; then
  "$SCRIPT_DIR/generate-claude-md.sh" >/dev/null
fi

if [[ "$DO_STAGE" == true && "$total" -gt 0 ]]; then
  all_copy=$(echo "$new_json $mod_json" | jq -sr '.[0] + .[1] | .[]')
  all_del=$(echo "$del_json" | jq -r '.[]')

  if [[ "$DIRECTION" == "user-to-repo" ]]; then
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      # README.md is at .cursor/ root, others are in subdirs
      if [[ "$f" == "README.md" ]]; then
        cp "$USER_DIR/$f" "$REPO_CURSOR/$f"
      else
        mkdir -p "$(dirname "$REPO_CURSOR/$f")"
        cp "$USER_DIR/$f" "$REPO_CURSOR/$f"
      fi
    done <<< "$all_copy"

    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      rm -f "$REPO_CURSOR/$f"
    done <<< "$all_del"

    cd "$REPO_DIR"
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      git add ".cursor/$f"
    done <<< "$all_copy"

    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      git rm -f --quiet ".cursor/$f" 2>/dev/null || true
    done <<< "$all_del"

    if [[ "$DO_COMMIT" == true ]]; then
      git commit -m "$COMMIT_MSG"
    fi
  else
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      if [[ "$f" == "README.md" ]]; then
        cp "$REPO_CURSOR/$f" "$USER_DIR/$f"
      else
        mkdir -p "$(dirname "$USER_DIR/$f")"
        cp "$REPO_CURSOR/$f" "$USER_DIR/$f"
      fi
    done <<< "$all_copy"

    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      rm -f "$USER_DIR/$f"
    done <<< "$all_del"
  fi
fi

jq -n \
  --arg repoDir "$REPO_DIR" \
  --argjson new "$new_json" \
  --argjson modified "$mod_json" \
  --argjson deleted "$del_json" \
  --argjson ignored "$ignored_json" \
  --argjson total "$total" \
  --arg staged "$DO_STAGE" \
  --arg committed "$DO_COMMIT" \
  '{repoDir: $repoDir, total: $total, new: $new, modified: $modified, deleted: $deleted, ignored: $ignored, staged: ($staged == "true"), committed: ($committed == "true")}'
