#!/usr/bin/env bash
# convention-sync.sh — Sync ~/.cursor/ files with the edge-conventions repo.
# Usage: ./convention-sync.sh <repo-dir> [--stage] [--commit -m "message"] [--repo-to-user]
# Compares ~/.cursor/{commands,rules,skills} against <repo-dir>/.cursor/ and
# outputs a structured JSON summary of new, modified, and deleted files.
# With --stage: copies changed files and stages them in git (or copies to user dir with --repo-to-user).
# With --commit: stages + commits (requires -m). Only valid for user-to-repo direction.

set -euo pipefail

REPO_DIR=""
DO_STAGE=false
DO_COMMIT=false
COMMIT_MSG=""
DIRECTION="user-to-repo"

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
  echo "Usage: convention-sync.sh <repo-dir> [--stage] [--commit -m \"message\"]" >&2
  exit 1
fi

if [[ "$DO_COMMIT" == true && -z "$COMMIT_MSG" ]]; then
  echo "ERROR: --commit requires -m \"message\"" >&2
  exit 1
fi

USER_DIR="$HOME/.cursor"
REPO_CURSOR="$REPO_DIR/.cursor"
DIRS="commands rules skills"

new_json="[]"
mod_json="[]"
del_json="[]"

for dir in $DIRS; do
  user_path="$USER_DIR/$dir"
  repo_path="$REPO_CURSOR/$dir"

  [[ -d "$user_path" ]] || continue

  while IFS= read -r rel; do
    [[ -z "$rel" ]] && continue
    repo_file="$repo_path/$rel"
    entry="$dir/$rel"
    if [[ ! -f "$repo_file" ]]; then
      new_json=$(echo "$new_json" | jq --arg f "$entry" '. + [$f]')
    elif ! diff -q "$user_path/$rel" "$repo_file" >/dev/null 2>&1; then
      mod_json=$(echo "$mod_json" | jq --arg f "$entry" '. + [$f]')
    fi
  done < <(cd "$user_path" && find . -type f ! -name '.DS_Store' | sed 's|^\./||')

  if [[ -d "$repo_path" ]]; then
    while IFS= read -r rel; do
      [[ -z "$rel" ]] && continue
      user_file="$user_path/$rel"
      entry="$dir/$rel"
      if [[ ! -f "$user_file" ]]; then
        del_json=$(echo "$del_json" | jq --arg f "$entry" '. + [$f]')
      fi
    done < <(cd "$repo_path" && find . -type f ! -name '.DS_Store' | sed 's|^\./||')
  fi
done

total=$(echo "$new_json $mod_json $del_json" | jq -s '.[0] + .[1] + .[2] | length')

if [[ "$DO_STAGE" == true && "$total" -gt 0 ]]; then
  all_copy=$(echo "$new_json $mod_json" | jq -sr '.[0] + .[1] | .[]')
  all_del=$(echo "$del_json" | jq -r '.[]')

  if [[ "$DIRECTION" == "user-to-repo" ]]; then
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      mkdir -p "$(dirname "$REPO_CURSOR/$f")"
      cp "$USER_DIR/$f" "$REPO_CURSOR/$f"
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
      mkdir -p "$(dirname "$USER_DIR/$f")"
      cp "$REPO_CURSOR/$f" "$USER_DIR/$f"
    done <<< "$all_copy"

    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      rm -f "$USER_DIR/$f"
    done <<< "$all_del"
  fi
fi

jq -n \
  --argjson new "$new_json" \
  --argjson modified "$mod_json" \
  --argjson deleted "$del_json" \
  --argjson total "$total" \
  --arg staged "$DO_STAGE" \
  --arg committed "$DO_COMMIT" \
  '{total: $total, new: $new, modified: $modified, deleted: $deleted, staged: ($staged == "true"), committed: ($committed == "true")}'
