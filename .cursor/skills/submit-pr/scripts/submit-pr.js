#!/usr/bin/env node
'use strict'

const { spawnSync } = require('child_process')
const fs = require('fs')
const path = require('path')

function printUsage() {
  process.stderr.write(
    [
      'Usage:',
      '  node submit-pr.js --repo <repo-path> [--plan <plan-doc>] [--base <branch>] [--title <title>] [--body-file <file>] [--draft]',
      '',
      'Examples:',
      '  node submit-pr.js --repo ~/git/edge-react-gui --plan ~/git/edge-plans/2026-02/example.md',
      '  node submit-pr.js --repo ~/git/edge-core-js --title "Fix wallet sync bug" --base master'
    ].join('\n') + '\n'
  )
}

function parseArgs(argv) {
  const opts = {
    draft: false
  }

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    if (arg === '--help' || arg === '-h') {
      opts.help = true
      continue
    }
    if (arg === '--draft') {
      opts.draft = true
      continue
    }
    if (arg === '--repo') {
      opts.repo = argv[++i]
      continue
    }
    if (arg === '--plan') {
      opts.plan = argv[++i]
      continue
    }
    if (arg === '--base') {
      opts.base = argv[++i]
      continue
    }
    if (arg === '--title') {
      opts.title = argv[++i]
      continue
    }
    if (arg === '--body-file') {
      opts.bodyFile = argv[++i]
      continue
    }
    throw new Error(`Unknown argument: ${arg}`)
  }

  if (opts.help) return opts
  if (!opts.repo) throw new Error('--repo is required')
  opts.repo = path.resolve(opts.repo)
  if (opts.plan) opts.plan = path.resolve(opts.plan)
  if (opts.bodyFile) opts.bodyFile = path.resolve(opts.bodyFile)
  return opts
}

function run(cmd, args, opts = {}) {
  const result = spawnSync(cmd, args, {
    cwd: opts.cwd,
    encoding: 'utf8',
    stdio: ['pipe', 'pipe', 'pipe']
  })

  if (result.error) throw result.error
  if (result.status !== 0) {
    const details = (result.stderr || result.stdout || '').trim()
    if (opts.allowFailure) return ''
    throw new Error(`${cmd} ${args.join(' ')} failed${details ? `: ${details}` : ''}`)
  }
  return (result.stdout || '').trim()
}

function ensureRepo(repoPath) {
  if (!fs.existsSync(repoPath)) throw new Error(`Repository path not found: ${repoPath}`)
  if (!fs.existsSync(path.join(repoPath, '.git'))) {
    throw new Error(`Not a git repository: ${repoPath}`)
  }
}

function ensureCleanWorkingTree(repoPath) {
  const status = run('git', ['status', '--porcelain=v1'], {
    cwd: repoPath,
    allowFailure: true
  })
  if (status.trim()) {
    throw new Error(
      'Working tree is not clean. Run cleanup-branch (and any final fixes) before submit-pr.'
    )
  }
}

function parseOwnerRepo(remoteUrl) {
  const match = remoteUrl.match(/github\.com[:/]([^/]+)\/([^/.]+)(?:\.git)?$/)
  if (!match) throw new Error(`Could not parse owner/repo from origin URL: ${remoteUrl}`)
  return {
    owner: match[1],
    repo: match[2]
  }
}

function getDefaultBaseBranch(repoPath) {
  const symbolic = run(
    'git',
    ['symbolic-ref', 'refs/remotes/origin/HEAD'],
    { cwd: repoPath, allowFailure: true }
  )
  if (symbolic && symbolic.includes('/')) {
    return symbolic.split('/').pop()
  }
  return 'master'
}

function humanizeBranch(branch) {
  return branch
    .split('/')
    .pop()
    .replace(/[-_]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
}

function toTitleCase(input) {
  return input
    .split(' ')
    .filter(Boolean)
    .map(word => word[0].toUpperCase() + word.slice(1))
    .join(' ')
}

function defaultTitle(repoName, branch) {
  const human = toTitleCase(humanizeBranch(branch))
  return human ? `${repoName}: ${human}` : `${repoName}: Update branch`
}

function defaultBody(opts, repoPath, branch, base) {
  const lines = [
    '## Summary',
    `- Publish updates from branch \`${branch}\` into \`${base}\`.`
  ]

  if (opts.plan) {
    lines.push(`- Planning document: \`${opts.plan}\`.`)
  }

  lines.push('', '## Test plan', '- [ ] Verify local checks passed before merge.')
  lines.push('- [ ] Validate key flows for affected repositories.')
  lines.push('', `Repository path: \`${repoPath}\``)
  return lines.join('\n')
}

function getExistingOpenPr(repoFullName, branch) {
  const output = run(
    'gh',
    [
      'pr',
      'list',
      '--repo',
      repoFullName,
      '--head',
      branch,
      '--state',
      'open',
      '--json',
      'url,number,title,baseRefName',
      '--limit',
      '1'
    ],
    { allowFailure: true }
  )
  if (!output) return null
  const prs = JSON.parse(output)
  return prs.length ? prs[0] : null
}

function main() {
  const opts = parseArgs(process.argv.slice(2))
  if (opts.help) {
    printUsage()
    return
  }

  ensureRepo(opts.repo)
  ensureCleanWorkingTree(opts.repo)

  if (opts.bodyFile && !fs.existsSync(opts.bodyFile)) {
    throw new Error(`Body file not found: ${opts.bodyFile}`)
  }

  const branch = run('git', ['branch', '--show-current'], { cwd: opts.repo })
  if (!branch) throw new Error('No current branch found')

  const remoteUrl = run('git', ['remote', 'get-url', 'origin'], { cwd: opts.repo })
  const parsed = parseOwnerRepo(remoteUrl)
  const repoFullName = `${parsed.owner}/${parsed.repo}`
  const base = opts.base || getDefaultBaseBranch(opts.repo)

  run('git', ['push', '-u', 'origin', 'HEAD'], { cwd: opts.repo })

  const existing = getExistingOpenPr(repoFullName, branch)
  if (existing) {
    console.log(
      JSON.stringify(
        {
          created: false,
          repo: repoFullName,
          branch,
          base: existing.baseRefName || base,
          prNumber: existing.number,
          prTitle: existing.title,
          prUrl: existing.url
        },
        null,
        2
      )
    )
    return
  }

  const title = opts.title || defaultTitle(parsed.repo, branch)
  const body = opts.bodyFile
    ? fs.readFileSync(opts.bodyFile, 'utf8')
    : defaultBody(opts, opts.repo, branch, base)

  const args = [
    'pr',
    'create',
    '--repo',
    repoFullName,
    '--head',
    branch,
    '--base',
    base,
    '--title',
    title,
    '--body',
    body
  ]
  if (opts.draft) args.push('--draft')

  const prUrl = run('gh', args, { cwd: opts.repo })

  console.log(
    JSON.stringify(
      {
        created: true,
        repo: repoFullName,
        branch,
        base,
        prTitle: title,
        prUrl
      },
      null,
      2
    )
  )
}

try {
  main()
} catch (error) {
  process.stderr.write(`[submit-pr] ${error.message}\n`)
  process.exit(1)
}
