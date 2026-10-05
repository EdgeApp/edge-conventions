#!/usr/bin/env node
'use strict'

// Submit a review document (from review-report.js) to a GitHub pull request,
// placing findings inline where their lines are in the diff.
//
//   node review-submit.js --repo <owner/repo> --pr <number> --review-file <path> [--event <EVENT>]
//
// The event is REQUEST_CHANGES with a critical finding, COMMENT with a warning,
// APPROVE otherwise — except on your own pull request, where GitHub accepts
// only COMMENT. --event overrides the choice.

const { execFileSync } = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

function ensureGhToken() {
  if (process.env.GH_TOKEN) return
  try {
    const b64 = execFileSync(
      'security',
      ['find-generic-password', '-s', 'gh:github.com', '-w'],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }
    ).trim()
    const match = b64.match(/^go-keyring-base64:(.+)$/)
    if (match) {
      process.env.GH_TOKEN = Buffer.from(match[1], 'base64').toString('utf8')
    } else if (b64.startsWith('gho_') || b64.startsWith('ghp_')) {
      process.env.GH_TOKEN = b64
    }
  } catch (_) {}
}

function gh(args) {
  try {
    return execFileSync('gh', args, {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      maxBuffer: 200 * 1024 * 1024
    }).trim()
  } catch (e) {
    const err = new Error(`gh ${args.join(' ')} failed: ${(e.stderr || e.message || '').toString().trim()}`)
    err.gh = true
    throw err
  }
}

function parseArgs(argv) {
  const opts = {}
  for (let i = 0; i < argv.length; i++) {
    if (argv[i].startsWith('--')) opts[argv[i].slice(2)] = argv[++i]
  }
  return opts
}

// ---------------------------------------------------------------------------
// Diff → commentable RIGHT-side lines. The API rejects inline comments on
// lines outside diff hunks, so only those lines get inline comments.
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
    const plus = raw.match(/^\+\+\+ b\/(.+)$/)
    if (plus && !inHunk) {
      // Authoritative new path (handles spaces and renames).
      if (plus[1] !== currentFile) {
        validLines[plus[1]] = validLines[currentFile] || new Set()
        delete validLines[currentFile]
        currentFile = plus[1]
      }
      continue
    }
    if (!inHunk && (raw.startsWith('--- ') || raw.startsWith('+++ '))) continue

    const hunkMatch = raw.match(/^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/)
    if (hunkMatch && currentFile) {
      rightLine = parseInt(hunkMatch[1])
      inHunk = true
      continue
    }
    if (!inHunk || !currentFile) continue

    if (raw.startsWith('+') || raw.startsWith(' ')) {
      validLines[currentFile].add(rightLine)
      rightLine++
    } else if (raw.startsWith('-') || raw.startsWith('\\')) {
      // Deletions have no right-side line; "\ No newline" is metadata.
    } else {
      inHunk = false
    }
  }
  return validLines
}

/** The PR diff; the per-file patches when GitHub refuses the full diff (too large). */
function fetchPrDiff(repo, prNumber) {
  try {
    return gh(['api', `repos/${repo}/pulls/${prNumber}`, '-H', 'Accept: application/vnd.github.v3.diff'])
  } catch (e) {
    process.stderr.write('Full diff unavailable; falling back to per-file patches\n')
    const files = gh(['api', '--paginate', `repos/${repo}/pulls/${prNumber}/files`, '--jq', '.[] | {filename, patch}'])
    return files
      .split('\n')
      .filter(Boolean)
      .map(line => JSON.parse(line))
      .filter(f => f.patch)
      .map(f => `diff --git a/${f.filename} b/${f.filename}\n--- a/${f.filename}\n+++ b/${f.filename}\n${f.patch}`)
      .join('\n')
  }
}

// ---------------------------------------------------------------------------
// Payload
// ---------------------------------------------------------------------------

const LABEL = { critical: 'Issue', warning: 'Warning', suggestion: 'Suggestion' }

function buildPayload({ findings, validLines, headSha, ownPr, event }) {
  const inlineComments = []
  const bodyFindings = []

  for (const f of findings) {
    const fileValid = f.file ? validLines[f.file] : null
    const targetLine = f.endLine || f.line
    if (!f.file || !f.line || !fileValid || !fileValid.has(targetLine)) {
      bodyFindings.push(f)
      continue
    }
    const commentBody =
      `**${LABEL[f.severity] || 'Suggestion'}:** ${f.message}` +
      (f.recommendation ? `\n\n**Recommendation:** ${f.recommendation}` : '')
    const c = { path: f.file, line: targetLine, side: 'RIGHT', body: commentBody }
    if (f.endLine && f.endLine > f.line) {
      // A multi-line comment must stay inside one hunk: every line commentable.
      let contiguous = true
      for (let n = f.line; n <= f.endLine; n++) if (!fileValid.has(n)) contiguous = false
      if (contiguous) {
        c.start_line = f.line
        c.start_side = 'RIGHT'
      }
    }
    inlineComments.push(c)
  }

  const hasCritical = findings.some(f => f.severity === 'critical')
  const hasWarnings = findings.some(f => f.severity === 'warning')
  let chosen = event || (hasCritical ? 'REQUEST_CHANGES' : hasWarnings ? 'COMMENT' : 'APPROVE')
  if (ownPr && chosen !== 'COMMENT') chosen = 'COMMENT'

  let body = ''
  if (bodyFindings.length) {
    body += '## Additional Findings\n\n'
    for (const f of bodyFindings) {
      const loc = f.file ? `\`${f.file}${f.line ? ':' + f.line : ''}\`` : ''
      body += `- **${f.severity}**${loc ? ' ' + loc : ''}: ${f.message}\n`
      if (f.recommendation) body += `  - ${f.recommendation}\n`
    }
  } else if (!inlineComments.length) {
    body = 'No issues found. Looks good!\n'
  } else {
    body = 'See inline comments.\n'
  }

  return { commit_id: headSha, event: chosen, body, comments: inlineComments }
}

function readFindings(reviewFile) {
  const content = fs.readFileSync(reviewFile, 'utf8')
  const jsonMatch = content.match(/<!-- FINDINGS_JSON\n([\s\S]*?)\nFINDINGS_JSON -->/)
  if (!jsonMatch) throw new Error('No embedded findings found in review file')
  return JSON.parse(jsonMatch[1])
}

function main(argv) {
  const opts = parseArgs(argv)
  const repo = opts.repo
  const prNumber = opts.pr
  const reviewFile = opts['review-file']
  if (!repo || !prNumber || !reviewFile) {
    process.stderr.write(
      'Usage: node review-submit.js --repo <owner/repo> --pr <number> --review-file <path> [--event APPROVE|COMMENT|REQUEST_CHANGES]\n'
    )
    process.exit(1)
  }
  if (!/^[\w.-]+\/[\w.-]+$/.test(repo) || !/^\d+$/.test(prNumber)) {
    process.stderr.write('--repo must be owner/repo and --pr a number\n')
    process.exit(1)
  }

  const findings = readFindings(reviewFile)
  process.stderr.write('Fetching PR diff from GitHub...\n')
  const validLines = parseDiffValidLines(fetchPrDiff(repo, prNumber))
  const pr = JSON.parse(gh(['pr', 'view', prNumber, '--repo', repo, '--json', 'headRefOid,author']))
  const me = gh(['api', 'user', '--jq', '.login'])
  const payload = buildPayload({
    findings,
    validLines,
    headSha: pr.headRefOid,
    ownPr: pr.author && pr.author.login === me,
    event: opts.event
  })
  process.stderr.write(
    `Submitting ${payload.event}: ${payload.comments.length} inline, ` +
      `${findings.length - payload.comments.length} in body\n`
  )

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'review-submit-'))
  const payloadFile = path.join(dir, 'payload.json')
  fs.writeFileSync(payloadFile, JSON.stringify(payload))
  const result = gh(['api', `repos/${repo}/pulls/${prNumber}/reviews`, '--method', 'POST', '--input', payloadFile])
  fs.rmSync(dir, { recursive: true, force: true })
  const obj = JSON.parse(result)
  console.log(obj.html_url || `Review submitted (ID: ${obj.id})`)
}

module.exports = { buildPayload, parseDiffValidLines, readFindings }

if (require.main === module) {
  ensureGhToken()
  try {
    main(process.argv.slice(2))
  } catch (e) {
    process.stderr.write(`${e.message}\n`)
    process.exit(1)
  }
}
