#!/usr/bin/env bash
# asana-get-context.sh
# Fetch concise context from an Asana task for implementation or PR creation.
#
# Usage:
#   asana-get-context.sh <task_gid_or_url>
#   asana-get-context.sh --task-url <url>
#   asana-get-context.sh --task <task_gid>
#
# Accepts a raw task GID or a full Asana URL. URL formats supported:
#   https://app.asana.com/0/<project_gid>/<task_gid>[/f]
#   https://app.asana.com/1/<project_gid>/task/<task_gid>[/f]
#
# Requires env var: ASANA_TOKEN
#
# Output (compact, agent-friendly):
#   TASK_NAME: <name>
#   TASK_DESCRIPTION: <notes, truncated to 500 chars>
#   PRIORITY: <value>
#   STATUS: <value>
#   IMPLEMENTOR: <name>
#   REVIEWER: <name>
#   COMMENTS: (most recent 5, one per block)
#   ATTACHMENTS: <count> files
#   DOWNLOADED: <count> files to <dir>
#   UNPACKED: <zip> -> <dir> (<count> files)     [if ZIPs present]
#   PDF_TEXT: <path> (from <file>, <chars> chars)  [if PDF has text]
#   PDF_PAGES: <dir> (<count> pages from <file>)   [if PDF is image-based]
set -euo pipefail

# Parse arguments: accept positional, --task, or --task-url
RAW_INPUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-url|--task)
      RAW_INPUT="${2:-}"
      shift 2
      ;;
    -*)
      echo "Unknown flag: $1" >&2
      exit 1
      ;;
    *)
      RAW_INPUT="$1"
      shift
      ;;
  esac
done

if [[ -z "$RAW_INPUT" ]]; then
  echo "Usage: asana-get-context.sh <task_gid_or_url>" >&2
  exit 1
fi

# Extract task GID: accept a raw numeric GID or any Asana URL containing one.
# Strips trailing path segments (/f, /subtask/…) and query strings.
if [[ "$RAW_INPUT" =~ /task/([0-9]+) ]]; then
  TASK_GID="${BASH_REMATCH[1]}"
elif [[ "$RAW_INPUT" =~ /([0-9]+)(/f)?([?#].*)?$ ]]; then
  TASK_GID="${BASH_REMATCH[1]}"
elif [[ "$RAW_INPUT" =~ ^[0-9]+$ ]]; then
  TASK_GID="$RAW_INPUT"
else
  echo "Error: could not extract task GID from: $RAW_INPUT" >&2
  exit 1
fi
if [[ -z "${ASANA_TOKEN:-}" ]]; then
  echo "Error: ASANA_TOKEN not set" >&2
  exit 1
fi

API="https://app.asana.com/api/1.0"
AUTH="Authorization: Bearer $ASANA_TOKEN"

# Fetch task + custom fields
curl -s "$API/tasks/$TASK_GID?opt_fields=name,notes,custom_fields.gid,custom_fields.name,custom_fields.display_value" \
  -H "$AUTH" | python3 -c "
import sys, json
data = json.load(sys.stdin)['data']

print(f\"TASK_NAME: {data['name']}\")

notes = (data.get('notes') or '').strip()
if len(notes) > 500:
    notes = notes[:500] + '...'
print(f\"TASK_DESCRIPTION: {notes or '(empty)'}\")

FIELDS = {
    '795866930204488': 'PRIORITY',
    '1190660107346181': 'STATUS',
    '1203334386796983': 'IMPLEMENTOR',
    '1203334388004673': 'REVIEWER',
}
for f in data.get('custom_fields', []):
    label = FIELDS.get(f['gid'])
    if label:
        val = f.get('display_value') or '(not set)'
        print(f'{label}: {val}')
"

# Fetch project memberships — look for version project (e.g. "4.44.0")
curl -s "$API/tasks/$TASK_GID?opt_fields=memberships.project.name" \
  -H "$AUTH" | python3 -c "
import sys, json, re
data = json.load(sys.stdin)['data']
for m in data.get('memberships', []):
    name = m.get('project', {}).get('name', '')
    if re.match(r'^\d+\.\d+\.\d+$', name):
        print(f'VERSION_PROJECT: {name}')
        break
else:
    print('VERSION_PROJECT: (not set)')
"

# Fetch recent comments (last 5)
curl -s "$API/tasks/$TASK_GID/stories?opt_fields=resource_subtype,text,created_by.name,created_at&limit=100" \
  -H "$AUTH" | python3 -c "
import sys, json
data = json.load(sys.stdin)['data']
comments = [s for s in data if s.get('resource_subtype') == 'comment_added'][-5:]
if not comments:
    print('COMMENTS: (none)')
else:
    print('COMMENTS:')
    for c in comments:
        author = c.get('created_by', {}).get('name', 'unknown')
        text = (c.get('text') or '').strip().replace('\n', ' ')
        if len(text) > 200:
            text = text[:200] + '...'
        date = c.get('created_at', '')[:10]
        print(f'  [{date}] {author}: {text}')
"

# Fetch attachments — download all supported types, then post-process
DOWNLOAD_DIR="/tmp/asana-task-$TASK_GID"

# Phase 1: Download all supported attachments
curl -s "$API/tasks/$TASK_GID/attachments?opt_fields=name,resource_subtype,download_url" \
  -H "$AUTH" | python3 -c "
import sys, json, os, urllib.request

data = json.load(sys.stdin)['data']
if not data:
    print('ATTACHMENTS: (none)')
    sys.exit(0)

DOWNLOAD_EXTS = {
    '.md', '.txt', '.json', '.csv', '.log', '.yaml', '.yml',
    '.pdf',
    '.zip',
    '.png', '.jpg', '.jpeg', '.gif', '.webp',
}
download_dir = '$DOWNLOAD_DIR'
downloaded = []

print(f'ATTACHMENTS: {len(data)} files')
for a in data:
    name = a.get('name', 'unnamed')
    url = a.get('download_url')
    ext = os.path.splitext(name)[1].lower()
    if ext in DOWNLOAD_EXTS and url:
        os.makedirs(download_dir, exist_ok=True)
        dest = os.path.join(download_dir, name)
        try:
            urllib.request.urlretrieve(url, dest)
            downloaded.append(dest)
            print(f'  - {name} (downloaded)')
        except Exception as e:
            print(f'  - {name} (download failed: {e})')
    else:
        print(f'  - {name}')

if downloaded:
    print(f'DOWNLOADED: {len(downloaded)} files to {download_dir}')
    for d in downloaded:
        print(f'  {d}')
"

# Phase 2: Unpack ZIP archives (may produce more files to process)
shopt -s nullglob
for zip_file in "$DOWNLOAD_DIR"/*.zip; do
  subdir="$DOWNLOAD_DIR/$(basename "$zip_file" .zip)"
  if unzip -o -q "$zip_file" -d "$subdir" 2>/dev/null; then
    file_count=$(find "$subdir" -type f 2>/dev/null | wc -l | tr -d ' ')
    echo "UNPACKED: $(basename "$zip_file") -> $subdir ($file_count files)"
    rm "$zip_file"
  else
    echo "UNPACK_FAILED: $(basename "$zip_file")"
  fi
done
shopt -u nullglob

# Phase 3: Process PDFs (text extraction first, image fallback)
process_pdf() {
  local pdf="$1"
  local base="${pdf%.pdf}"
  local fname
  fname="$(basename "$pdf")"

  if command -v pdftotext &>/dev/null; then
    local text
    text=$(pdftotext "$pdf" - 2>/dev/null || true)
    local char_count
    char_count=$(printf '%s' "$text" | tr -d '[:space:]' | wc -c | tr -d ' ')
    if [[ "$char_count" -gt 100 ]]; then
      printf '%s' "$text" > "${base}.txt"
      echo "PDF_TEXT: ${base}.txt (from $fname, ${char_count} chars)"
      return
    fi
  fi

  if command -v pdftoppm &>/dev/null; then
    local pages_dir="${base}_pages"
    mkdir -p "$pages_dir"
    pdftoppm -png -r 150 "$pdf" "$pages_dir/page" 2>/dev/null
    local page_count
    page_count=$(find "$pages_dir" -name 'page-*.png' 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$page_count" -gt 0 ]]; then
      echo "PDF_PAGES: $pages_dir ($page_count pages from $fname)"
    else
      echo "PDF_CONVERT_FAILED: $fname"
    fi
  else
    echo "PDF_SKIPPED: $fname (install poppler-utils for text/image extraction)"
  fi
}

if [[ -d "$DOWNLOAD_DIR" ]]; then
  while IFS= read -r pdf; do
    process_pdf "$pdf"
  done < <(find "$DOWNLOAD_DIR" -name '*.pdf' -type f 2>/dev/null)
fi
