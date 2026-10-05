#!/usr/bin/env node
'use strict'

// Prepare a code review: resolve what is being reviewed, write its diff to
// disk, pick the review subagents, and gather prior review comments.
//
//   node review-prep.js [--base <ref>] [--repo-dir <path>] <input>
//
// <input> is one of:
//   https://github.com/<owner>/<repo>/pull/<n>   a pull request
//   <n> | #<n>                                    a pull request in the repo at --repo-dir / cwd
//   <A>..<B>                                      a commit range: the diff from A to B
//   <A>...<B>                                     a commit range from merge-base(A, B) to B
//   <branch>                                      a branch, against its base
//   current                                       HEAD, against its base (or uncommitted changes)
//
// Nothing is checked out, reset, or switched: every diff is computed from
// refs, so the review is safe to run in a checkout with work in progress.
// Subagents read files at `headSha` with `git -C <repoDir> show <headSha>:<path>`.

const { execFileSync } = require('child_process')
const fs = require('fs')
const path = require('path')

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

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

class PrepError extends Error {}

/** Run a program with arguments (never through a shell). */
function run(file, args, opts = {}) {
  const { cwd, allowFailure } = opts
  try {
    return execFileSync(file, args, {
      encoding: 'utf8',
      cwd,
      maxBuffer: 200 * 1024 * 1024,
      stdio: ['ignore', 'pipe', 'pipe']
    }).replace(/\s+$/, '')
  } catch (e) {
    if (allowFailure) return ''
    throw new PrepError(
      `Command failed: ${file} ${args.join(' ')}\n${(e.stderr || e.message || '').toString().trim()}`
    )
  }
}

const git = (cwd, ...args) => run('git', args, { cwd })
const tryGit = (cwd, ...args) => run('git', args, { cwd, allowFailure: true })
const hasRef = (cwd, ref) =>
  tryGit(cwd, 'rev-parse', '--verify', '-q', `${ref}^{commit}`) !== ''

function log(msg) {
  process.stderr.write(msg + '\n')
}

// ---------------------------------------------------------------------------
// Input parsing
// ---------------------------------------------------------------------------

function parseArgs(argv) {
  const flags = {}
  const positional = []
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--base') flags.base = argv[++i]
    else if (argv[i] === '--repo-dir') flags.repoDir = argv[++i]
    else positional.push(argv[i])
  }
  return { flags, input: positional[0] }
}

function classify(input) {
  const url = input.match(/github\.com\/([^/]+)\/([^/]+)\/pull\/(\d+)/)
  if (url) {
    return { mode: 'pr', owner: url[1], repo: url[2], prNumber: parseInt(url[3]) }
  }
  const num = input.match(/^#?(\d+)$/)
  if (num) return { mode: 'pr', prNumber: parseInt(num[1]) }
  const range = input.match(/^(.+?)(\.\.\.?)(.+)$/)
  if (range) {
    return { mode: 'range', from: range[1], to: range[3], symmetric: range[2] === '...' }
  }
  if (input === 'current') return { mode: 'current' }
  return { mode: 'branch', branch: input }
}

// ---------------------------------------------------------------------------
// Repo discovery
// ---------------------------------------------------------------------------

/** owner/repo from the origin remote, or null. */
function originSlug(dir) {
  const url = tryGit(dir, 'remote', 'get-url', 'origin')
  const m = url.match(/github\.com[:/]([^/]+)\/([^/]+?)(?:\.git)?\/?$/)
  return m ? { owner: m[1], repo: m[2] } : null
}

/** The repository's own name — the main clone's directory, not a worktree's. */
function cloneName(dir) {
  const common = tryGit(dir, 'rev-parse', '--path-format=absolute', '--git-common-dir')
  return common ? path.basename(path.dirname(common)) : path.basename(dir)
}

function findRepoDir(target, flags, conventionsDir) {
  if (flags.repoDir) return path.resolve(flags.repoDir)
  const cwd = process.cwd()
  if (!target.repo) return cwd
  const slug = originSlug(cwd)
  if (slug && slug.repo.toLowerCase() === target.repo.toLowerCase()) return cwd
  const dir = path.join(path.resolve(conventionsDir, '..'), target.repo)
  if (!fs.existsSync(dir)) throw new PrepError(`Repository not found at ${dir}`)
  return dir
}

// ---------------------------------------------------------------------------
// Base ref
// ---------------------------------------------------------------------------

/** A remote-tracking ref for bare branch names ("develop" → "origin/develop"). */
function normalizeRef(dir, ref) {
  if (ref !== 'HEAD' && !ref.includes('/') && hasRef(dir, `refs/remotes/origin/${ref}`)) {
    return `origin/${ref}`
  }
  if (!hasRef(dir, ref)) throw new PrepError(`Unknown ref: ${ref}`)
  return ref
}

/**
 * The branch the head forked from: origin/master or origin/develop, by
 * merge-base ancestry; origin/HEAD's target when that cannot decide.
 */
function defaultBase(dir, head) {
  const m = hasRef(dir, 'origin/master')
  const d = hasRef(dir, 'origin/develop')
  const originHead = tryGit(dir, 'symbolic-ref', '-q', '--short', 'refs/remotes/origin/HEAD')
  if (m && d) {
    const mbM = tryGit(dir, 'merge-base', head, 'origin/master')
    const mbD = tryGit(dir, 'merge-base', head, 'origin/develop')
    if (mbM && mbD) {
      if (mbM === mbD) return 'origin/master'
      if (isAncestor(dir, mbM, mbD)) return 'origin/develop'
      if (isAncestor(dir, mbD, mbM)) return 'origin/master'
    }
  }
  if (originHead) return originHead
  if (m) return 'origin/master'
  if (d) return 'origin/develop'
  throw new PrepError('Cannot determine the base branch; pass --base <ref>')
}

function isAncestor(dir, a, b) {
  try {
    execFileSync('git', ['merge-base', '--is-ancestor', a, b], { cwd: dir, stdio: 'ignore' })
    return true
  } catch (_) {
    return false
  }
}

// ---------------------------------------------------------------------------
// Diff parsing
// ---------------------------------------------------------------------------

/** Split a unified diff into { newPath: section }, honouring renames. */
function parseDiffByFile(raw) {
  const result = {}
  for (const part of raw.split(/^(?=diff --git )/m)) {
    if (!part.startsWith('diff --git ')) continue
    const plus = part.match(/^\+\+\+ b\/(.+)$/m)
    const renameTo = part.match(/^rename to (.+)$/m)
    const header = part.match(/^diff --git a\/.+ b\/(.+)$/m)
    const file = plus ? plus[1] : renameTo ? renameTo[1] : header ? header[1] : null
    if (file) result[file] = part
  }
  return result
}

// ---------------------------------------------------------------------------
// Subagent selection
// ---------------------------------------------------------------------------

/** Agent names from .cursor/agents/*.md. */
function listAgents(conventionsDir) {
  const dir = path.join(conventionsDir, '.cursor', 'agents')
  if (!fs.existsSync(dir)) return []
  return fs
    .readdirSync(dir)
    .filter(f => f.endsWith('.md'))
    .sort()
    .map(f => {
      const text = fs.readFileSync(path.join(dir, f), 'utf8')
      const m = text.match(/^name:\s*(\S+)/m)
      return m ? m[1] : f.replace(/\.md$/, '')
    })
}

function selectSubagents({ agents, changedFiles, fileDiffs, isServer }) {
  const filesWithPattern = pattern =>
    changedFiles.filter(f => fileDiffs[f] && pattern.test(fileDiffs[f]))
  const tsxFiles = changedFiles.filter(f => /\.tsx$/.test(f))
  const localeFiles = changedFiles.filter(f => /locale|strings|i18n|l10n|enUS/i.test(f))
  const serviceFiles = changedFiles.filter(f => /\/services\//i.test(f))

  const rules = {
    'review-react': () => tsxFiles,
    'review-async': () => [
      ...new Set([
        ...filesWithPattern(/\b(setInterval|setTimeout|makePeriodicTask)\b|async\s+\w/),
        ...serviceFiles
      ])
    ],
    'review-state': () =>
      filesWithPattern(/\b(useState|useSelector|useReducer|DataStore)\b|from\s+['"].*redux/),
    'review-cleaners': () =>
      filesWithPattern(
        /\b(asObject|asString|asNumber|asBoolean|asArray|asOptional|asMaybe|asEither|asDate|asJSON|asUnknown|asValue|asMap|asCleaner|uncleaner)\b|from\s+['"]cleaners['"]/
      ),
    'review-errors': () => filesWithPattern(/\btry\s*\{|\bcatch\s*\(|\bthrow\s|\.\s*catch\s*\(/),
    'review-strings': () => [...new Set([...tsxFiles, ...localeFiles])],
    'review-servers': () => (isServer ? changedFiles : false),
    'review-performance': () =>
      filesWithPattern(
        /\b(useWatch|withWallet|YAOB|onBlockHeightChanged|onSyncStatusChanged|onNewTokens|onTransactions|EngineEmitter|BLOCK_HEIGHT_CHANGED|ADDRESSES_CHECKED|TRANSACTIONS|updateBlockHeight|onSeenTxCheckpoint|reportDetectedTokens|onStakingStatusChanged|InteractionManager|transitionStart|currencyWallets|saveWalletLoop|updateQueue|makeEngineEmitter)\b/
      ),
    'review-code-quality': () => changedFiles,
    'review-comments': () => changedFiles,
    'review-tests': () => changedFiles,
    'review-pr': () => true,
    'review-repo': () => true
  }

  const subagents = {}
  for (const name of agents) {
    if (rules[name]) subagents[name] = rules[name]()
    else {
      // A reviewer this script has no rule for still reviews every file.
      log(`No selection rule for ${name}; giving it every changed file`)
      subagents[name] = changedFiles
    }
  }
  return subagents
}

// ---------------------------------------------------------------------------
// Existing reviews (PRs only)
// ---------------------------------------------------------------------------

function jsonLines(text) {
  const out = []
  for (const line of text.split('\n')) {
    if (!line.trim()) continue
    try {
      out.push(JSON.parse(line))
    } catch (_) {}
  }
  return out
}

function fetchExistingReviews(dir, owner, repo, prNumber) {
  const reviews = jsonLines(
    run(
      'gh',
      [
        'api', '--paginate', `repos/${owner}/${repo}/pulls/${prNumber}/reviews`,
        '--jq', '.[] | select(.state != "PENDING") | {user: .user.login, state: .state, body: .body}'
      ],
      { cwd: dir, allowFailure: true }
    )
  )
  const comments = jsonLines(
    run(
      'gh',
      [
        'api', '--paginate', `repos/${owner}/${repo}/pulls/${prNumber}/comments`,
        '--jq', '.[] | {user: .user.login, path: .path, line: .line, body: .body}'
      ],
      { cwd: dir, allowFailure: true }
    )
  ).map(c => `${c.user} on ${c.path}:${c.line}: ${c.body}`)
  return reviews.concat(comments)
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

function prepare(argv) {
  const { flags, input } = parseArgs(argv)
  if (!input) {
    throw new PrepError(
      'Usage: node review-prep.js [--base <ref>] [--repo-dir <path>] ' +
        '<pr-url | pr-number | A..B | A...B | branch-name | "current">'
    )
  }
  const target = classify(input)
  const conventionsDir = path.resolve(__dirname, '..', '..', '..', '..')
  const repoDir = findRepoDir(target, flags, conventionsDir)
  const slug = originSlug(repoDir)
  const owner = target.owner || (slug ? slug.owner : 'unknown')
  const repo = target.repo || (slug ? slug.repo : cloneName(repoDir))
  log(`Repo: ${owner}/${repo} at ${repoDir}`)

  try {
    execFileSync('git', ['fetch', '--quiet', 'origin'], { cwd: repoDir, stdio: 'ignore' })
  } catch (_) {
    log('Warning: could not fetch origin; using the remote-tracking refs already present')
  }

  let prNumber = target.prNumber || null
  let prUrl = null
  let branch = null
  let baseRef = null
  let baseSha
  let headSha
  let mergeBase
  let uncommitted = false

  if (target.mode === 'pr') {
    log(`Fetching PR #${prNumber}...`)
    const meta = JSON.parse(
      run(
        'gh',
        ['pr', 'view', String(prNumber), '--repo', `${owner}/${repo}`, '--json', 'headRefName,headRefOid,baseRefName,url'],
        { cwd: repoDir }
      )
    )
    branch = meta.headRefName
    prUrl = meta.url
    headSha = meta.headRefOid
    // Works for branches and forks alike, without adding remotes.
    if (!hasRef(repoDir, headSha)) {
      git(repoDir, 'fetch', '--quiet', 'origin', `refs/pull/${prNumber}/head`)
    }
    if (!hasRef(repoDir, headSha)) throw new PrepError(`PR head ${headSha} is not available locally`)
    baseRef = normalizeRef(repoDir, flags.base || meta.baseRefName)
    log(`Base: ${baseRef}  Head: ${branch} @ ${headSha.slice(0, 10)}`)
  } else if (target.mode === 'range') {
    if (flags.base) log('Ignoring --base: a range names its own base')
    // A range is taken literally, the way git reads it.
    for (const ref of [target.from, target.to]) {
      if (!hasRef(repoDir, ref)) throw new PrepError(`Unknown ref: ${ref}`)
    }
    headSha = git(repoDir, 'rev-parse', `${target.to}^{commit}`)
    const from = git(repoDir, 'rev-parse', `${target.from}^{commit}`)
    baseRef = target.from
    mergeBase = target.symmetric ? git(repoDir, 'merge-base', from, headSha) : from
    const tips = tryGit(repoDir, 'for-each-ref', '--points-at', headSha, '--format=%(refname:short)', 'refs/heads')
    branch = tips.split('\n').filter(Boolean)[0] || null
  } else {
    branch =
      target.mode === 'branch' ? target.branch : tryGit(repoDir, 'branch', '--show-current') || null
    const headRef =
      target.mode === 'current'
        ? 'HEAD'
        : hasRef(repoDir, `refs/heads/${branch}`)
          ? `refs/heads/${branch}`
          : hasRef(repoDir, `refs/remotes/origin/${branch}`)
            ? `origin/${branch}`
            : null
    if (!headRef) throw new PrepError(`Branch not found locally or on origin: ${branch}`)
    headSha = git(repoDir, 'rev-parse', `${headRef}^{commit}`)
    baseRef = flags.base ? normalizeRef(repoDir, flags.base) : defaultBase(repoDir, headSha)
  }

  baseSha = git(repoDir, 'rev-parse', `${baseRef}^{commit}`)
  mergeBase = mergeBase || git(repoDir, 'merge-base', baseSha, headSha)

  // ---- Diff ---------------------------------------------------------------
  log('Generating diff...')
  const diffArgs = ['--no-color', '--no-ext-diff', '-M']
  let diff
  let changedFiles
  let diffSummary
  const committed = mergeBase !== headSha
  if (target.mode === 'current' && !committed) {
    // Nothing committed on top of the base: review the working tree.
    uncommitted = true
    diff = git(repoDir, 'diff', ...diffArgs, 'HEAD')
    changedFiles = git(repoDir, 'diff', '--name-only', '-M', 'HEAD').split('\n').filter(Boolean)
    diffSummary = (git(repoDir, 'diff', '--stat', 'HEAD').split('\n').pop() || '').trim()
  } else {
    diff = git(repoDir, 'diff', ...diffArgs, mergeBase, headSha)
    changedFiles = git(repoDir, 'diff', '--name-only', '-M', mergeBase, headSha).split('\n').filter(Boolean)
    diffSummary = (git(repoDir, 'diff', '--stat', mergeBase, headSha).split('\n').pop() || '').trim()
  }

  const id = prNumber ? `pr-${prNumber}` : (branch || 'range').replace(/[^A-Za-z0-9._-]+/g, '-')
  const diffFile = `/tmp/review-${repo}-${id}-${headSha.slice(0, 10)}${uncommitted ? '-wip' : ''}.diff`
  fs.writeFileSync(diffFile, diff + '\n')
  log(`${changedFiles.length} files changed → ${diffFile}`)

  // ---- Subagents ------------------------------------------------------------
  log('Selecting subagents...')
  const hasPm2 =
    tryGit(repoDir, 'cat-file', '-t', `${headSha}:pm2.json`) === 'blob' ||
    (uncommitted && fs.existsSync(path.join(repoDir, 'pm2.json')))
  const subagents = selectSubagents({
    agents: listAgents(conventionsDir),
    changedFiles,
    fileDiffs: parseDiffByFile(diff),
    isServer: repo.endsWith('-server') || hasPm2
  })

  const existingReviews = prNumber ? fetchExistingReviews(repoDir, owner, repo, prNumber) : []

  return {
    repo,
    owner,
    mode: target.mode,
    branch,
    baseBranch: baseRef,
    baseSha,
    mergeBase,
    headSha,
    range: target.mode === 'range' ? input : null,
    uncommitted,
    prNumber,
    prUrl,
    isLocalBranch: target.mode !== 'pr',
    repoDir,
    changedFiles,
    diffFile,
    subagents,
    existingReviews,
    diffSummary
  }
}

module.exports = { classify, parseDiffByFile, selectSubagents, prepare }

if (require.main === module) {
  ensureGhToken()
  try {
    console.log(JSON.stringify(prepare(process.argv.slice(2)), null, 2))
  } catch (e) {
    if (!(e instanceof PrepError)) throw e
    log(e.message)
    process.exit(1)
  }
}
