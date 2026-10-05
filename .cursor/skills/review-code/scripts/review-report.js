#!/usr/bin/env node
'use strict'

// Merge review findings into a markdown review document in /tmp.
//
//   node review-report.js --manifest <manifest.json> --findings <findings.json>
//
// Findings: [{ severity, file, line, endLine, message, recommendation }].
// severity is critical | warning | suggestion; numeric 0-3 and the common
// synonyms (blocker, high, medium, low, nit, …) are mapped onto those three.

const fs = require('fs')

const SEVERITY = {
  critical: 'critical',
  blocker: 'critical',
  0: 'critical',
  warning: 'warning',
  high: 'warning',
  major: 'warning',
  medium: 'warning',
  1: 'warning',
  2: 'warning',
  suggestion: 'suggestion',
  low: 'suggestion',
  minor: 'suggestion',
  nit: 'suggestion',
  3: 'suggestion'
}

function normalizeSeverity(severity) {
  return SEVERITY[String(severity).trim().toLowerCase()] || null
}

function parseArgs(argv) {
  const opts = {}
  for (let i = 0; i < argv.length; i++) {
    if (argv[i].startsWith('--')) opts[argv[i].slice(2)] = argv[++i]
  }
  return opts
}

/** Drop findings already raised in existing PR reviews. */
function dedupe(findings, existingReviews) {
  if (!existingReviews || !existingReviews.length) return findings
  const existingText = existingReviews
    .map(r => (typeof r === 'string' ? r : r.body || ''))
    .join('\n')
    .toLowerCase()
  return findings.filter(f => {
    const key = (f.message || '').toLowerCase().slice(0, 60)
    return key.length < 10 || !existingText.includes(key)
  })
}

function renderSection(title, items) {
  if (!items.length) return ''
  let s = `## ${title}\n\n`
  for (const f of items) {
    const loc = f.file ? `\`${f.file}${f.line ? ':' + f.line : ''}\`` : ''
    s += `- ${loc}${loc ? ' — ' : ''}${f.message}\n`
    if (f.recommendation) s += `  - **Fix**: ${f.recommendation}\n`
  }
  return s + '\n'
}

function buildReport({ manifest, findings, repoName, branch, prNumber, now }) {
  findings = dedupe(findings, manifest.existingReviews).map(f => ({
    ...f,
    severity: normalizeSeverity(f.severity) || f.severity
  }))
  const critical = findings.filter(f => f.severity === 'critical')
  const warnings = findings.filter(f => f.severity === 'warning')
  const suggestions = findings.filter(f => f.severity === 'suggestion')
  const other = findings.filter(f => !normalizeSeverity(f.severity))

  let md = `# Code Review: ${repoName}\n\n`
  md += `**Branch**: ${branch}\n`
  if (prNumber) md += `**PR**: #${prNumber}\n`
  if (manifest.range) md += `**Range**: ${manifest.range}\n`
  md += `**Date**: ${now.toISOString().slice(0, 16).replace('T', ' ')}\n`
  md += `**Summary**: ${manifest.diffSummary || `${findings.length} findings`}\n\n`
  md += renderSection('Critical Issues', critical)
  md += renderSection('Warnings', warnings)
  md += renderSection('Suggestions', suggestions)
  md += renderSection('Other (unrecognised severity)', other)
  if (!findings.length) md += '## Summary\n\nNo issues found. Code looks good!\n'
  // "-->" inside a message would close the comment early; > parses back to ">".
  const json = JSON.stringify(findings).replace(/-->/g, '--\\u003e')
  md += `\n<!-- FINDINGS_JSON\n${json}\nFINDINGS_JSON -->\n`
  return { md, findings }
}

/** /tmp/MMDDHHmm_<repo>_<branch>_<pr-N|review>.md, never overwriting an earlier report. */
function reportPath({ repoName, branch, prNumber, now }) {
  const ts = [now.getMonth() + 1, now.getDate(), now.getHours(), now.getMinutes()]
    .map(n => String(n).padStart(2, '0'))
    .join('')
  const prSuffix = prNumber ? `_pr-${prNumber}` : '_review'
  const safeBranch = String(branch).replace(/[^A-Za-z0-9._-]+/g, '-')
  const stem = `/tmp/${ts}_${repoName}_${safeBranch}${prSuffix}`
  let file = `${stem}.md`
  for (let n = 2; fs.existsSync(file); n++) file = `${stem}-${n}.md`
  return file
}

function main(argv) {
  const opts = parseArgs(argv)
  const manifest = opts.manifest ? JSON.parse(fs.readFileSync(opts.manifest, 'utf8')) : {}
  let findings = []
  if (opts.findings) {
    findings = JSON.parse(fs.readFileSync(opts.findings, 'utf8'))
  } else if (!process.stdin.isTTY) {
    const stdin = fs.readFileSync(0, 'utf8')
    if (stdin.trim()) findings = JSON.parse(stdin)
  } else {
    process.stderr.write('Usage: node review-report.js --manifest <file> --findings <file>\n')
    process.exit(1)
  }
  if (!Array.isArray(findings)) throw new Error('findings must be a JSON array')

  const now = new Date()
  const ctx = {
    manifest,
    repoName: opts.repo || manifest.repo || 'unknown',
    branch: opts.branch || manifest.branch || 'unknown',
    prNumber: opts.pr || manifest.prNumber,
    now
  }
  const { md } = buildReport({ ...ctx, findings })
  const filepath = reportPath(ctx)
  fs.writeFileSync(filepath, md)
  console.log(filepath)
}

module.exports = { buildReport, dedupe, normalizeSeverity, reportPath }

if (require.main === module) main(process.argv.slice(2))
