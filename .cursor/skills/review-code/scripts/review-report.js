#!/usr/bin/env node
'use strict'

const fs = require('fs')

// ---------------------------------------------------------------------------
// Argument parsing
// ---------------------------------------------------------------------------

const args = process.argv.slice(2)
const opts = {}
for (let i = 0; i < args.length; i++) {
  if (args[i].startsWith('--')) opts[args[i].slice(2)] = args[++i]
}

// ---------------------------------------------------------------------------
// Load manifest & findings
// ---------------------------------------------------------------------------

let manifest = {}
if (opts.manifest) {
  manifest = JSON.parse(fs.readFileSync(opts.manifest, 'utf8'))
}

let findings = []
if (opts.findings) {
  findings = JSON.parse(fs.readFileSync(opts.findings, 'utf8'))
} else {
  const stdin = fs.readFileSync('/dev/stdin', 'utf8')
  if (stdin.trim()) findings = JSON.parse(stdin)
}

const repoName = opts.repo || manifest.repo || 'unknown'
const branch = opts.branch || manifest.branch || 'unknown'
const prNumber = opts.pr || manifest.prNumber

// ---------------------------------------------------------------------------
// Deduplicate against existing reviews
// ---------------------------------------------------------------------------

const existingReviews = manifest.existingReviews || []

if (existingReviews.length) {
  const existingText = existingReviews
    .map(r => (typeof r === 'string' ? r : r.body || ''))
    .join('\n')
    .toLowerCase()

  findings = findings.filter(f => {
    const key = (f.message || '').toLowerCase().slice(0, 60)
    return key.length < 10 || !existingText.includes(key)
  })
}

// ---------------------------------------------------------------------------
// Categorise
// ---------------------------------------------------------------------------

const critical = findings.filter(f => f.severity === 'critical')
const warnings = findings.filter(f => f.severity === 'warning')
const suggestions = findings.filter(f => f.severity === 'suggestion')

// ---------------------------------------------------------------------------
// Build markdown
// ---------------------------------------------------------------------------

const now = new Date()
const ts = [
  String(now.getMonth() + 1).padStart(2, '0'),
  String(now.getDate()).padStart(2, '0'),
  String(now.getHours()).padStart(2, '0'),
  String(now.getMinutes()).padStart(2, '0')
].join('')

const prSuffix = prNumber ? `_pr-${prNumber}` : '_review'
const safeBranch = branch.replace(/\//g, '-')
const filename = `${ts}_${repoName}_${safeBranch}${prSuffix}.md`
const filepath = `/tmp/${filename}`

function renderSection(title, items) {
  if (!items.length) return ''
  let s = `## ${title}\n\n`
  for (const f of items) {
    const loc = f.file
      ? `\`${f.file}${f.line ? ':' + f.line : ''}\``
      : ''
    s += `- ${loc}${loc ? ' — ' : ''}${f.message}\n`
    if (f.recommendation) s += `  - **Fix**: ${f.recommendation}\n`
  }
  return s + '\n'
}

let md = `# Code Review: ${repoName}\n\n`
md += `**Branch**: ${branch}\n`
if (prNumber) md += `**PR**: #${prNumber}\n`
md += `**Date**: ${now.toISOString().slice(0, 16).replace('T', ' ')}\n`
md += `**Summary**: ${manifest.diffSummary || `${findings.length} findings`}\n\n`

md += renderSection('Critical Issues', critical)
md += renderSection('Warnings', warnings)
md += renderSection('Suggestions', suggestions)

if (!findings.length) {
  md += '## Summary\n\nNo issues found. Code looks good!\n'
}

md += `\n<!-- FINDINGS_JSON\n${JSON.stringify(findings)}\nFINDINGS_JSON -->\n`

fs.writeFileSync(filepath, md)
console.log(filepath)
