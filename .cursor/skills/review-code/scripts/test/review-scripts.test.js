'use strict'

// node --test .cursor/skills/review-code/scripts/test/*.test.js
//
// Builds throwaway repos with a bare origin; a stub `gh` stands in for GitHub.

const assert = require('assert/strict')
const { execFileSync, spawnSync } = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')
const test = require('node:test')

const { classify, parseDiffByFile, selectSubagents } = require('../review-prep.js')
const { buildReport, normalizeSeverity, reportPath } = require('../review-report.js')
const { buildPayload, parseDiffValidLines } = require('../review-submit.js')

const SCRIPTS = path.resolve(__dirname, '..')
const env = {
  ...process.env,
  GIT_CONFIG_GLOBAL: '/dev/null',
  GIT_CONFIG_NOSYSTEM: '1',
  GIT_AUTHOR_NAME: 'T',
  GIT_AUTHOR_EMAIL: 't@example.com',
  GIT_COMMITTER_NAME: 'T',
  GIT_COMMITTER_EMAIL: 't@example.com',
  GH_TOKEN: 'test'
}
const made = []
test.after(() => made.forEach(d => fs.rmSync(d, { recursive: true, force: true })))

const g = (cwd, ...args) => execFileSync('git', args, { cwd, env, encoding: 'utf8' }).trim()
function commit(dir, msg, files) {
  for (const [f, t] of Object.entries(files)) {
    fs.mkdirSync(path.dirname(path.join(dir, f)), { recursive: true })
    fs.writeFileSync(path.join(dir, f), t)
  }
  g(dir, 'add', '-A')
  g(dir, 'commit', '-q', '-m', msg)
  return g(dir, 'rev-parse', 'HEAD')
}

/** origin with master and develop; the clone's local develop is left stale. */
function sandbox() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'review-code-'))
  made.push(dir)
  const origin = path.join(dir, 'origin.git')
  const repo = path.join(dir, 'demo')
  g(dir, 'init', '-q', '--bare', '-b', 'master', origin)
  g(dir, 'clone', '-q', origin, repo)
  g(repo, 'checkout', '-q', '-b', 'master')
  commit(repo, 'init', { 'a.txt': 'a\n' })
  g(repo, 'push', '-q', '-u', 'origin', 'master')
  g(repo, 'checkout', '-q', '-b', 'develop')
  commit(repo, 'dev', { 'dev.txt': 'd\n' })
  g(repo, 'push', '-q', '-u', 'origin', 'develop')
  g(repo, 'checkout', '-q', '-b', 'paul/feat')
  commit(repo, 'feat', { 'src/Scene.tsx': 'export const A = () => { try { x() } catch (e) {} }\n' })
  // Upstream moves on; the local develop does not.
  g(repo, 'checkout', '-q', 'develop')
  commit(repo, 'dev2', { 'dev2.txt': 'd2\n' })
  g(repo, 'push', '-q')
  g(repo, 'reset', '-q', '--hard', 'HEAD~1')
  g(repo, 'checkout', '-q', 'paul/feat')
  return { dir, origin, repo }
}

function prep(cwd, args, extraEnv = {}) {
  const res = spawnSync('node', [path.join(SCRIPTS, 'review-prep.js'), ...args], {
    cwd,
    env: { ...env, ...extraEnv },
    encoding: 'utf8'
  })
  if (res.status !== 0) throw new Error(`prep failed: ${res.stderr}`)
  return JSON.parse(res.stdout)
}

test('classify recognises every input form', () => {
  assert.deepEqual(classify('https://github.com/EdgeApp/edge-core-js/pull/12'), {
    mode: 'pr', owner: 'EdgeApp', repo: 'edge-core-js', prNumber: 12
  })
  assert.deepEqual(classify('#7'), { mode: 'pr', prNumber: 7 })
  assert.deepEqual(classify('abc123..def456'), { mode: 'range', from: 'abc123', to: 'def456', symmetric: false })
  assert.deepEqual(classify('origin/develop...HEAD'), { mode: 'range', from: 'origin/develop', to: 'HEAD', symmetric: true })
  assert.deepEqual(classify('current'), { mode: 'current' })
  assert.deepEqual(classify('paul/feat'), { mode: 'branch', branch: 'paul/feat' })
})

test('branch review diffs against origin, not a stale local base', () => {
  const { repo } = sandbox()
  const m = prep(repo, ['current'])
  assert.equal(m.baseBranch, 'origin/develop')
  assert.deepEqual(m.changedFiles, ['src/Scene.tsx'])
  // --base is honoured, and a bare name means the origin branch.
  const m2 = prep(repo, ['--base', 'master', 'current'])
  assert.equal(m2.baseBranch, 'origin/master')
  assert.deepEqual(m2.changedFiles.sort(), ['dev.txt', 'src/Scene.tsx'])
  assert.ok(fs.readFileSync(m.diffFile, 'utf8').includes('Scene.tsx'))
})

test('nothing is checked out, switched, or reset', () => {
  const { repo } = sandbox()
  g(repo, 'checkout', '-q', 'master')
  fs.appendFileSync(path.join(repo, 'a.txt'), 'wip\n')
  const m = prep(repo, ['paul/feat'])
  assert.deepEqual(m.changedFiles, ['src/Scene.tsx'])
  assert.equal(g(repo, 'branch', '--show-current'), 'master')
  assert.equal(g(repo, 'status', '--porcelain'), 'M a.txt')
})

test('a commit range reviews exactly that range', () => {
  const { repo } = sandbox()
  const first = g(repo, 'rev-parse', 'HEAD')
  commit(repo, 'second', { 'src/second.ts': 'export async function load() {}\n' })
  const m = prep(repo, [`${first}..HEAD`])
  assert.equal(m.mode, 'range')
  assert.equal(m.mergeBase, first)
  assert.deepEqual(m.changedFiles, ['src/second.ts'])
  assert.equal(m.branch, 'paul/feat')
  assert.deepEqual(m.subagents['review-async'], ['src/second.ts'])
  const sym = prep(repo, ['origin/develop...HEAD'])
  assert.deepEqual(sym.changedFiles.sort(), ['src/Scene.tsx', 'src/second.ts'])
})

test('uncommitted changes are reviewed when nothing is committed', () => {
  const { repo } = sandbox()
  g(repo, 'checkout', '-q', '-b', 'paul/wip', 'origin/develop')
  fs.writeFileSync(path.join(repo, 'dev.txt'), 'changed\n')
  const m = prep(repo, ['current'])
  assert.equal(m.uncommitted, true)
  assert.deepEqual(m.changedFiles, ['dev.txt'])
})

test('branch names are never run through a shell', () => {
  const { repo, dir } = sandbox()
  const marker = path.join(dir, 'PWNED')
  spawnSync('node', [path.join(SCRIPTS, 'review-prep.js'), `x;touch\${IFS}${marker};`], { cwd: repo, env })
  assert.equal(fs.existsSync(marker), false)
})

test('worktrees report the repository name from origin, not the folder', () => {
  const { repo, dir } = sandbox()
  const wt = path.join(dir, 'demo_feat2')
  g(repo, 'worktree', 'add', '-q', '-b', 'paul/feat2', wt, 'origin/develop')
  commit(wt, 'x', { 'x.ts': 'x\n' })
  g(repo, 'remote', 'set-url', 'origin', 'https://github.com/EdgeApp/edge-demo.git')
  const m = prep(wt, ['--base', 'refs/remotes/origin/develop', 'current'])
  assert.equal(m.repo, 'edge-demo')
  assert.equal(m.owner, 'EdgeApp')
})

test('a PR is fetched by refs/pull/N/head without checkout', () => {
  const { repo, dir } = sandbox()
  const head = commit(repo, 'pr work', { 'pr.ts': 'export const p = 1\n' })
  g(repo, 'push', '-q', 'origin', 'HEAD:refs/pull/7/head')
  g(repo, 'reset', '-q', '--hard', 'HEAD~1')
  g(repo, 'checkout', '-q', 'master')
  const bin = path.join(dir, 'bin')
  fs.mkdirSync(bin)
  fs.writeFileSync(
    path.join(bin, 'gh'),
    `#!/bin/sh\nif [ "$1" = pr ]; then echo '{"headRefName":"fork-branch","headRefOid":"${head}","baseRefName":"develop","url":"https://github.com/EdgeApp/demo/pull/7"}'; fi\n`
  )
  fs.chmodSync(path.join(bin, 'gh'), 0o755)
  const m = prep(repo, ['--repo-dir', repo, '7'], { PATH: `${bin}:${process.env.PATH}` })
  assert.equal(m.headSha, head)
  assert.equal(m.baseBranch, 'origin/develop')
  assert.deepEqual(m.changedFiles.sort(), ['pr.ts', 'src/Scene.tsx'])
  assert.equal(g(repo, 'branch', '--show-current'), 'master')
  assert.deepEqual(m.existingReviews, [])
})

test('subagents: every agent file is covered; renamed files match', () => {
  const diff = [
    'diff --git a/old.ts b/new.ts',
    'similarity index 90%',
    'rename from old.ts',
    'rename to new.ts',
    '--- a/old.ts',
    '+++ b/new.ts',
    '@@ -1 +1 @@',
    '-x',
    '+setTimeout(f, 1)'
  ].join('\n')
  const byFile = parseDiffByFile(diff)
  assert.deepEqual(Object.keys(byFile), ['new.ts'])
  const s = selectSubagents({
    agents: ['review-async', 'review-repo', 'review-servers', 'review-new-thing'],
    changedFiles: ['new.ts'],
    fileDiffs: byFile,
    isServer: false
  })
  assert.deepEqual(s, {
    'review-async': ['new.ts'],
    'review-repo': true,
    'review-servers': false,
    'review-new-thing': ['new.ts']
  })
})

test('report: severities are normalised, nothing is dropped, comments stay closed', () => {
  assert.equal(normalizeSeverity(0), 'critical')
  assert.equal(normalizeSeverity('High'), 'warning')
  assert.equal(normalizeSeverity('nit'), 'suggestion')
  const { md, findings } = buildReport({
    manifest: { range: 'a..b', existingReviews: ['bot on x.ts:1: Missing await on the save call'] },
    findings: [
      { severity: 1, file: 'a.ts', line: 3, message: 'uses --> arrow in text' },
      { severity: 'weird', message: 'odd severity kept' },
      { severity: 'warning', message: 'Missing await on the save call' }
    ],
    repoName: 'demo',
    branch: 'paul/x',
    now: new Date('2026-10-05T12:00:00Z')
  })
  assert.match(md, /## Warnings\n\n- `a.ts:3` — uses --> arrow/)
  assert.match(md, /## Other \(unrecognised severity\)\n\n- odd severity kept/)
  assert.match(md, /\*\*Range\*\*: a\.\.b/)
  assert.equal(findings.length, 2)
  const json = md.match(/<!-- FINDINGS_JSON\n([\s\S]*?)\nFINDINGS_JSON -->/)[1]
  assert.ok(!json.includes('-->'))
  assert.equal(JSON.parse(json)[0].message, 'uses --> arrow in text')
  const now = new Date()
  const p1 = reportPath({ repoName: 'demo-test', branch: 'b', prNumber: null, now })
  fs.writeFileSync(p1, 'x')
  const p2 = reportPath({ repoName: 'demo-test', branch: 'b', prNumber: null, now })
  fs.rmSync(p1)
  assert.notEqual(p1, p2)
})

test('submit: commentable lines, multi-line ranges, own-PR event', () => {
  const diff = [
    'diff --git a/a.ts b/a.ts',
    '--- a/a.ts',
    '+++ b/a.ts',
    '@@ -1,2 +1,3 @@',
    ' one',
    '+two',
    ' three',
    '@@ -10,1 +11,2 @@',
    '+eleven',
    ' twelve'
  ].join('\n')
  const valid = parseDiffValidLines(diff)
  assert.deepEqual([...valid['a.ts']], [1, 2, 3, 11, 12])
  const findings = [
    { severity: 'warning', file: 'a.ts', line: 2, endLine: 3, message: 'm1' },
    { severity: 'warning', file: 'a.ts', line: 3, endLine: 11, message: 'spans hunks' },
    { severity: 'critical', file: 'a.ts', line: 50, message: 'outside the diff' }
  ]
  const p = buildPayload({ findings, validLines: valid, headSha: 'abc', ownPr: false })
  assert.equal(p.event, 'REQUEST_CHANGES')
  assert.equal(p.comments[0].start_line, 2)
  assert.equal(p.comments[1].start_line, undefined)
  assert.equal(p.comments[1].line, 11)
  assert.match(p.body, /outside the diff/)
  assert.equal(buildPayload({ findings, validLines: valid, headSha: 'abc', ownPr: true }).event, 'COMMENT')
  assert.equal(buildPayload({ findings: [], validLines: valid, headSha: 'abc', ownPr: false }).event, 'APPROVE')
})
