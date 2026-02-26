#!/usr/bin/env node
'use strict'

const { execSync } = require('child_process')
const fs = require('fs')
const { ensureGhToken } = require('./gh-token')

ensureGhToken()

function run(cmd) {
  return execSync(cmd, {
    encoding: 'utf8',
    stdio: ['pipe', 'pipe', 'pipe'],
    maxBuffer: 50 * 1024 * 1024
  }).trim()
}

// ---------------------------------------------------------------------------
// Argument parsing
// ---------------------------------------------------------------------------

const args = process.argv.slice(2)
const opts = {}
for (let i = 0; i < args.length; i++) {
  if (args[i].startsWith('--')) opts[args[i].slice(2)] = args[++i]
}

const repoFullName = opts.repo
const prNumber = opts.pr
const reviewFile = opts['review-file']

if (!repoFullName || !prNumber || !reviewFile) {
  process.stderr.write(
    'Usage: node review-submit.js --repo <owner/repo> --pr <number> --review-file <path>\n'
  )
  process.exit(1)
}

// ---------------------------------------------------------------------------
// Parse review document
// ---------------------------------------------------------------------------

const content = fs.readFileSync(reviewFile, 'utf8')
const jsonMatch = content.match(
  /<!-- FINDINGS_JSON\n([\s\S]*?)\nFINDINGS_JSON -->/
)
if (!jsonMatch) {
  process.stderr.write('No embedded findings found in review file\n')
  process.exit(1)
}

const findings = JSON.parse(jsonMatch[1])

// ---------------------------------------------------------------------------
// Fetch the PR diff from GitHub and parse valid RIGHT-side line numbers.
// The API rejects inline comments on lines outside diff hunks, so we need
// to know exactly which lines are commentable.
// ---------------------------------------------------------------------------

function parseDiffValidLines(diffContent) {
  const validLines = {} // { filepath: Set<lineNumber> }
  let currentFile = null
  let rightLine = 0
  let inHunk = false

  for (const raw of diffContent.split('\n')) {
    const fileMatch = raw.match(/^diff --git a\/.+ b\/(.+)$/)
    if (fileMatch) {
      currentFile = fileMatch[1]
      if (!validLines[currentFile]) validLines[currentFile] = new Set()
      inHunk = false
      continue
    }

    if (raw.startsWith('--- ') || raw.startsWith('+++ ')) continue

    const hunkMatch = raw.match(/^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/)
    if (hunkMatch && currentFile) {
      rightLine = parseInt(hunkMatch[1])
      inHunk = true
      continue
    }

    if (!inHunk || !currentFile) continue

    if (raw.startsWith('+')) {
      validLines[currentFile].add(rightLine)
      rightLine++
    } else if (raw.startsWith('-')) {
      // Deletions have no right-side line number
    } else if (raw.startsWith(' ')) {
      validLines[currentFile].add(rightLine)
      rightLine++
    } else if (raw.startsWith('\\')) {
      // "\ No newline at end of file" — skip
    } else {
      inHunk = false
    }
  }

  return validLines
}

process.stderr.write('Fetching PR diff from GitHub...\n')

const prDiff = run(
  `gh api repos/${repoFullName}/pulls/${prNumber} ` +
    '-H "Accept: application/vnd.github.v3.diff"'
)
const validLines = parseDiffValidLines(prDiff)

// ---------------------------------------------------------------------------
// Build review payload
// ---------------------------------------------------------------------------

const headSha = run(
  `gh pr view ${prNumber} --repo ${repoFullName} --json headRefOid --jq .headRefOid`
)

const inlineComments = []
const bodyFindings = []

for (const f of findings) {
  if (!f.file || !f.line) {
    bodyFindings.push(f)
    continue
  }

  const severity =
    f.severity === 'critical'
      ? 'Issue'
      : f.severity === 'warning'
        ? 'Warning'
        : 'Suggestion'

  const fileValid = validLines[f.file]
  const targetLine = f.endLine || f.line

  if (fileValid && fileValid.has(targetLine)) {
    // Line is inside a diff hunk — inline comment
    const commentBody =
      `**${severity}:** ${f.message}` +
      (f.recommendation ? `\n\n**Recommendation:** ${f.recommendation}` : '')

    const c = { path: f.file, line: targetLine, side: 'RIGHT', body: commentBody }
    if (f.endLine && f.endLine !== f.line && fileValid.has(f.line)) {
      c.start_line = f.line
      c.start_side = 'RIGHT'
    }
    inlineComments.push(c)
  } else {
    // Line not in diff or file not in diff — include in body
    bodyFindings.push(f)
  }
}

const hasCritical = findings.some(f => f.severity === 'critical')
const hasWarnings = findings.some(f => f.severity === 'warning')
const event = hasCritical
  ? 'REQUEST_CHANGES'
  : hasWarnings
    ? 'COMMENT'
    : 'APPROVE'

let body = ''
if (bodyFindings.length) {
  body += '## Additional Findings\n\n'
  for (const f of bodyFindings) {
    const loc = f.file
      ? `\`${f.file}${f.line ? ':' + f.line : ''}\``
      : ''
    body += `- **${f.severity}**${loc ? ' ' + loc : ''}: ${f.message}\n`
    if (f.recommendation) body += `  - ${f.recommendation}\n`
  }
}
if (!bodyFindings.length && !inlineComments.length) {
  body = 'No issues found. Looks good!\n'
} else if (!bodyFindings.length) {
  body = 'See inline comments.\n'
}

process.stderr.write(
  `Submitting: ${inlineComments.length} inline, ${bodyFindings.length} in body\n`
)

// ---------------------------------------------------------------------------
// Submit
// ---------------------------------------------------------------------------

const payload = { commit_id: headSha, event, body, comments: inlineComments }
const payloadFile = `/tmp/review-payload-${prNumber}.json`
fs.writeFileSync(payloadFile, JSON.stringify(payload))

const result = run(
  `gh api repos/${repoFullName}/pulls/${prNumber}/reviews --method POST --input ${payloadFile}`
)
const obj = JSON.parse(result)
console.log(obj.html_url || `Review submitted (ID: ${obj.id})`)
