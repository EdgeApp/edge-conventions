#!/usr/bin/env node
'use strict'

const { execSync } = require('child_process')
const path = require('path')
const fs = require('fs')
const { ensureGhToken } = require('./gh-token')

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ensureGhToken()

function run(cmd, opts = {}) {
  const { cwd, allowFailure, maxBuffer = 50 * 1024 * 1024 } = opts
  try {
    return execSync(cmd, {
      encoding: 'utf8',
      cwd,
      maxBuffer,
      stdio: ['pipe', 'pipe', 'pipe']
    }).trim()
  } catch (e) {
    if (allowFailure) return ''
    process.stderr.write(`Command failed: ${cmd}\n${e.stderr || e.message}\n`)
    process.exit(1)
  }
}

function log(msg) {
  process.stderr.write(msg + '\n')
}

// ---------------------------------------------------------------------------
// Input parsing
// ---------------------------------------------------------------------------

const rawArgs = process.argv.slice(2)
const flags = {}
const positional = []
for (let i = 0; i < rawArgs.length; i++) {
  if (rawArgs[i] === '--base') flags.base = rawArgs[++i]
  else positional.push(rawArgs[i])
}

const input = positional[0]
if (!input) {
  log('Usage: node review-prep.js [--base <branch>] <pr-url | pr-number | branch-name | "current">')
  process.exit(1)
}

let prNumber = null
let owner = null
let repo = null
let prUrl = null
let branchName = null
let isLocalBranch = false

const prUrlMatch = input.match(
  /github\.com\/([^/]+)\/([^/]+)\/pull\/(\d+)/
)
const prNumberMatch = input.match(/^#?(\d+)$/)

if (prUrlMatch) {
  ;[, owner, repo] = prUrlMatch
  prNumber = parseInt(prUrlMatch[3])
  prUrl = `https://github.com/${owner}/${repo}/pull/${prNumber}`
} else if (prNumberMatch) {
  prNumber = parseInt(prNumberMatch[1])
} else if (input === 'current') {
  isLocalBranch = true
} else {
  branchName = input
  isLocalBranch = true
}

// ---------------------------------------------------------------------------
// Repo discovery
// ---------------------------------------------------------------------------

const conventionsDir = path.resolve(__dirname, '..', '..', '..', '..')
const reposParent = path.resolve(conventionsDir, '..')

let repoDir

if (isLocalBranch || (!owner && prNumber)) {
  repoDir = process.cwd()
  repo = repo || path.basename(repoDir)
  const remoteUrl = run('git remote get-url origin', {
    cwd: repoDir,
    allowFailure: true
  })
  const m = remoteUrl.match(/github\.com[:/]([^/]+)\//)
  owner = owner || (m ? m[1] : 'unknown')
} else {
  repoDir = path.join(reposParent, repo)
  if (!fs.existsSync(repoDir)) {
    log(`Repository not found at ${repoDir}`)
    process.exit(1)
  }
}

log(`Repo: ${owner}/${repo} at ${repoDir}`)

// ---------------------------------------------------------------------------
// PR metadata & checkout  /  local branch setup
// ---------------------------------------------------------------------------

let baseBranch

if (prNumber) {
  log(`Fetching PR #${prNumber}...`)
  const prMeta = JSON.parse(
    run(
      `gh pr view ${prNumber} --repo ${owner}/${repo} ` +
        '--json headRefName,headRepositoryOwner,baseRefName,url',
      { cwd: repoDir }
    )
  )

  branchName = prMeta.headRefName
  baseBranch = flags.base || prMeta.baseRefName
  const headOwner = prMeta.headRepositoryOwner.login
  prUrl = prUrl || prMeta.url
  const isFork = headOwner !== owner

  log(
    `Base: ${baseBranch}  Head: ${headOwner}:${branchName}  Fork: ${isFork}`
  )

  run('git fetch origin', { cwd: repoDir })

  if (isFork) {
    const remotes = run('git remote -v', { cwd: repoDir })
    if (!remotes.includes(headOwner)) {
      log(`Adding remote ${headOwner}...`)
      run(
        `git remote add ${headOwner} https://github.com/${headOwner}/${repo}.git`,
        { cwd: repoDir }
      )
    }
    run(`git fetch ${headOwner}`, { cwd: repoDir })
    run(`git checkout -B pr-${prNumber} ${headOwner}/${branchName}`, {
      cwd: repoDir
    })
  } else {
    const cur = run('git branch --show-current', {
      cwd: repoDir,
      allowFailure: true
    })
    if (cur !== branchName) {
      run(`git checkout -B ${branchName} origin/${branchName}`, {
        cwd: repoDir
      })
    } else {
      run(`git reset --hard origin/${branchName}`, { cwd: repoDir })
    }
  }
} else {
  // Local branch
  if (branchName) {
    const cur = run('git branch --show-current', {
      cwd: repoDir,
      allowFailure: true
    })
    if (cur !== branchName) {
      run(`git checkout ${branchName}`, { cwd: repoDir })
    }
  } else {
    branchName = run('git branch --show-current', { cwd: repoDir })
  }

  baseBranch =
    flags.base ||
    run(
      "git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'",
      { cwd: repoDir, allowFailure: true }
    ) ||
    'master'
}

// ---------------------------------------------------------------------------
// Diff generation
// ---------------------------------------------------------------------------

log('Generating diff...')

let diff
let changedFiles

const hasCommits = run(`git log --oneline ${baseBranch}..HEAD`, {
  cwd: repoDir,
  allowFailure: true
})

if (isLocalBranch && !hasCommits) {
  // Uncommitted-only changes
  const unstaged = run('git diff', { cwd: repoDir, allowFailure: true })
  const staged = run('git diff --cached', { cwd: repoDir, allowFailure: true })
  diff = [unstaged, staged].filter(Boolean).join('\n')

  const uFiles = run('git diff --name-only', {
    cwd: repoDir,
    allowFailure: true
  })
    .split('\n')
    .filter(Boolean)
  const sFiles = run('git diff --cached --name-only', {
    cwd: repoDir,
    allowFailure: true
  })
    .split('\n')
    .filter(Boolean)
  changedFiles = [...new Set([...uFiles, ...sFiles])]
} else {
  diff = run(`git diff ${baseBranch}...HEAD`, { cwd: repoDir })
  changedFiles = run(`git diff --name-only ${baseBranch}...HEAD`, {
    cwd: repoDir
  })
    .split('\n')
    .filter(Boolean)
}

const diffFile = `/tmp/review-${repo}-${prNumber || branchName.replace(/\//g, '-')}.diff`
fs.writeFileSync(diffFile, diff)

const diffStatRaw = run(
  hasCommits
    ? `git diff --stat ${baseBranch}...HEAD`
    : 'git diff --stat',
  { cwd: repoDir, allowFailure: true }
)
const diffSummary = (diffStatRaw.split('\n').pop() || '').trim()

log(`${changedFiles.length} files changed → ${diffFile}`)

// ---------------------------------------------------------------------------
// Subagent selection
// ---------------------------------------------------------------------------

log('Selecting subagents...')

function parseDiffByFile(raw) {
  const result = {}
  for (const part of raw.split(/^diff --git /m).filter(Boolean)) {
    const m = part.match(/^a\/(.+?) b\/(.+)$/m)
    if (m) {
      result[m[1]] = part
      result[m[2]] = part
    }
  }
  return result
}

const fileDiffs = parseDiffByFile(diff)

function filesWithPattern(pattern) {
  return changedFiles.filter(f => fileDiffs[f] && pattern.test(fileDiffs[f]))
}

const tsxFiles = changedFiles.filter(f => /\.tsx$/.test(f))
const localeFiles = changedFiles.filter(f =>
  /locale|strings|i18n|l10n|enUS/i.test(f)
)
const serviceFiles = changedFiles.filter(f => /\/services\//i.test(f))
const hasPm2 = fs.existsSync(path.join(repoDir, 'pm2.json'))
const isServer = repo.endsWith('-server') || hasPm2

const subagents = {
  'review-react': tsxFiles.length ? tsxFiles : [],

  'review-async': [
    ...new Set([
      ...filesWithPattern(
        /\b(setInterval|setTimeout|makePeriodicTask)\b|async\s+\w/
      ),
      ...serviceFiles
    ])
  ],

  'review-state': filesWithPattern(
    /\b(useState|useSelector|useReducer|DataStore)\b|from\s+['"].*redux/
  ),

  'review-cleaners': filesWithPattern(
    /\b(asObject|asString|asNumber|asBoolean|asArray|asOptional|asMaybe|asEither|asDate|asJSON|asUnknown|asValue|asMap|asCleaner|uncleaner)\b|from\s+['"]cleaners['"]/
  ),

  'review-errors': filesWithPattern(
    /\btry\s*\{|\bcatch\s*\(|\bthrow\s|\.\s*catch\s*\(/
  ),

  'review-strings': [...new Set([...tsxFiles, ...localeFiles])],

  'review-servers': isServer ? changedFiles : false,

  'review-code-quality': changedFiles,
  'review-comments': changedFiles,
  'review-tests': changedFiles,
  'review-pr': true
}

// ---------------------------------------------------------------------------
// Existing reviews (PRs only)
// ---------------------------------------------------------------------------

let existingReviews = []

if (prNumber) {
  log('Fetching existing reviews...')
  const revJson = run(
    `gh api repos/${owner}/${repo}/pulls/${prNumber}/reviews ` +
      "--jq '[.[] | select(.state != \"PENDING\") | {user: .user.login, state: .state, body: .body}]'",
    { cwd: repoDir, allowFailure: true }
  )
  if (revJson) {
    try {
      existingReviews = JSON.parse(revJson)
    } catch (_) {}
  }

  const cmtJson = run(
    `gh api repos/${owner}/${repo}/pulls/${prNumber}/comments ` +
      "--jq '[.[] | {user: .user.login, path: .path, line: .line, body: .body}]'",
    { cwd: repoDir, allowFailure: true }
  )
  if (cmtJson) {
    try {
      const cmts = JSON.parse(cmtJson)
      existingReviews = existingReviews.concat(
        cmts.map(c => `${c.user} on ${c.path}:${c.line}: ${c.body}`)
      )
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// Output manifest
// ---------------------------------------------------------------------------

const manifest = {
  repo,
  owner,
  branch: branchName,
  baseBranch,
  prNumber,
  prUrl,
  isLocalBranch,
  repoDir,
  changedFiles,
  diffFile,
  subagents,
  existingReviews,
  diffSummary
}

console.log(JSON.stringify(manifest, null, 2))
