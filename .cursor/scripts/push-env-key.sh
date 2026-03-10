#!/usr/bin/env bash
# push-env-key.sh — Update a single key in the server's env.json and push
#
# Usage: push-env-key.sh <KEY> <VALUE> [-m "commit message"]
#
# Examples:
#   push-env-key.sh EDGE_API_KEY abc123
#   push-env-key.sh EDGE_API_KEY abc123 -m "Rotate Edge API key"

set -euo pipefail

SERVER="jack"
REMOTE_REPO="/home/jon/jenkins-files/master"

KEY=""
VALUE=""
COMMIT_MSG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -m) COMMIT_MSG="$2"; shift 2 ;;
    *)
      if [[ -z "$KEY" ]]; then KEY="$1"
      elif [[ -z "$VALUE" ]]; then VALUE="$1"
      else echo "Unexpected argument: $1" >&2; exit 1
      fi
      shift ;;
  esac
done

if [[ -z "$KEY" || -z "$VALUE" ]]; then
  echo "Usage: push-env-key.sh <KEY> <VALUE> [-m \"commit message\"]" >&2
  exit 1
fi

if [[ -z "$COMMIT_MSG" ]]; then
  COMMIT_MSG="Update $KEY in env.json"
fi

ssh "$SERVER" bash -s -- "$KEY" "$VALUE" "$COMMIT_MSG" "$REMOTE_REPO" <<'REMOTE'
  set -euo pipefail
  KEY="$1"
  VALUE="$2"
  MSG="$3"
  REPO="$4"

  cd "$REPO"
  git pull --ff-only

  CURRENT=$(jq -r --arg k "$KEY" '.[$k] // empty' env.json)
  if [[ "$CURRENT" == "$VALUE" ]]; then
    echo "No change: $KEY is already set to that value."
    exit 0
  fi

  jq --arg k "$KEY" --arg v "$VALUE" '.[$k] = $v' env.json > env.json.tmp
  mv env.json.tmp env.json

  git add env.json
  git commit -m "$MSG"
  git push
  echo "Done: $KEY updated and pushed."
REMOTE
