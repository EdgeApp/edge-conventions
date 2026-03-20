#!/usr/bin/env bash
# asana-whoami.sh
# Resolve the current Asana user's GID from $ASANA_TOKEN.
# Caches the result in /tmp for the duration of the session.
#
# Usage:
#   asana-whoami.sh           # prints GID
#   asana-whoami.sh --name    # prints "GID NAME"
#
# Requires env var: ASANA_TOKEN
#
# Output:
#   <gid>              (default)
#   <gid> <name>       (with --name)
set -euo pipefail

SHOW_NAME=false
if [[ "${1:-}" == "--name" ]]; then
  SHOW_NAME=true
fi

if [[ -z "${ASANA_TOKEN:-}" ]]; then
  echo "Error: ASANA_TOKEN not set" >&2
  exit 1
fi

CACHE_FILE="/tmp/asana-whoami-$(echo "$ASANA_TOKEN" | shasum -a 256 | cut -c1-16).json"

if [[ -f "$CACHE_FILE" ]]; then
  cached=$(cat "$CACHE_FILE")
else
  cached=$(curl -s "https://app.asana.com/api/1.0/users/me?opt_fields=gid,name" \
    -H "Authorization: Bearer $ASANA_TOKEN")
  echo "$cached" > "$CACHE_FILE"
fi

if [[ "$SHOW_NAME" == "true" ]]; then
  echo "$cached" | python3 -c "
import sys, json
d = json.load(sys.stdin)['data']
print(f\"{d['gid']} {d['name']}\")
"
else
  echo "$cached" | python3 -c "
import sys, json
print(json.load(sys.stdin)['data']['gid'])
"
fi
