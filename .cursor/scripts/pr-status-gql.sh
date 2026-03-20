#!/usr/bin/env bash
# pr-status-gql.sh — Fetch status of open PRs for a user (GraphQL API).
# Single run, no TUI. "New" comments = posted after the PR's last commit.
#
# Uses a single GraphQL query per poll. Separate rate limit budget from REST.
#
# Usage:
#   pr-status-gql.sh --repo edge-react-gui [--owner EdgeApp] [--user Jon-edge] [--format text|json]
#   pr-status-gql.sh                       # All repos for user in EdgeApp org
#   pr-status-gql.sh --budget 0.5          # Reserve 50% of rate limit for other tools
#
# Requires: gh CLI (authenticated).
set -euo pipefail

OWNER="EdgeApp" REPO="" USER="" FORMAT="text" BUDGET="0.67"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner) OWNER="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --user) USER="$2"; shift 2 ;;
    --format) FORMAT="$2"; shift 2 ;;
    --budget) BUDGET="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

STATE_DIR="${TMPDIR:-/tmp}/pr-watch-gql-${OWNER}-${REPO:-all}"
mkdir -p "$STATE_DIR"
export STATE_DIR

# Build the GraphQL query based on mode (single repo vs all repos)
PR_FIELDS='
  number title isDraft url headRefName updatedAt
  repository { name nameWithOwner }
  headRefOid
  reviewDecision
  reviews(last: 30) {
    nodes { author { login } state submittedAt }
  }
  comments(last: 100) {
    totalCount
    nodes { author { login } createdAt bodyText }
  }
  reviewThreads(first: 100) {
    nodes {
      isResolved
      comments(first: 5) {
        nodes { author { login } createdAt bodyText path line }
      }
    }
  }
  commits(last: 1) {
    nodes {
      commit {
        committedDate
        oid
        statusCheckRollup {
          contexts(first: 20) {
            nodes {
              ... on CheckRun {
                __typename name status conclusion
              }
              ... on StatusContext {
                __typename context state
              }
            }
          }
        }
      }
    }
  }
'

if [[ -n "$REPO" ]]; then
  QUERY="
  {
    viewer { login }
    repository(owner: \"${OWNER}\", name: \"${REPO}\") {
      pullRequests(first: 50, states: OPEN, orderBy: {field: UPDATED_AT, direction: DESC}) {
        nodes {
          author { login }
          ${PR_FIELDS}
        }
      }
    }
    rateLimit { cost remaining resetAt limit }
  }"
else
  QUERY="
  {
    viewer {
      login
      pullRequests(first: 50, states: OPEN, orderBy: {field: UPDATED_AT, direction: DESC}) {
        nodes {
          ${PR_FIELDS}
        }
      }
    }
    rateLimit { cost remaining resetAt limit }
  }"
fi

# Execute query via gh CLI
GQL_RESULT=$(gh api graphql -f query="$QUERY" 2>&1)

# Process the result with Node.js
exec node -e '
const fs = require("fs")
const { OWNER, REPO, USER_ARG, FORMAT, BUDGET, STATE_DIR } = {
  OWNER: process.argv[1],
  REPO: process.argv[2] || "",
  USER_ARG: process.argv[3],
  FORMAT: process.argv[4],
  BUDGET: parseFloat(process.argv[5]) || 0.67,
  STATE_DIR: process.argv[6]
}
const gqlResult = JSON.parse(process.argv[7])

if (gqlResult.errors) {
  process.stderr.write("GraphQL errors: " + JSON.stringify(gqlResult.errors) + "\n")
  process.exit(1)
}

const data = gqlResult.data

// --- Determine user and extract raw PR nodes ---
let user
let rawNodes

if (REPO) {
  // Single-repo mode: repository.pullRequests, filtered by viewer login
  user = USER_ARG || data.viewer?.login || "unknown"
  rawNodes = (data.repository?.pullRequests?.nodes || [])
    .filter(n => n.author?.login === user)
} else {
  // All-repo mode: viewer.pullRequests (already scoped to authenticated user)
  user = data.viewer?.login || USER_ARG || "unknown"
  rawNodes = data.viewer?.pullRequests?.nodes || []
}

// --- Rate limit ---
const rateLimit = data.rateLimit || {}
const rlCost = rateLimit.cost || 1
const rlRemaining = rateLimit.remaining
const rlLimit = rateLimit.limit
const rlResetAt = rateLimit.resetAt

// --- NEW PR tracking ---
function loadPreviousPrNumbers() {
  try { return JSON.parse(fs.readFileSync(`${STATE_DIR}/known-prs.json`, "utf8")) } catch { return [] }
}
function savePrNumbers(numbers) {
  fs.writeFileSync(`${STATE_DIR}/known-prs.json`, JSON.stringify(numbers))
}

const previousPrNumbers = loadPreviousPrNumbers()
const currentPrNumbers = rawNodes.map(n => n.number)
const newPrNumbers = new Set(currentPrNumbers.filter(n => !previousPrNumbers.includes(n)))
savePrNumbers(currentPrNumbers)

// --- Transform GQL nodes to result format ---
function checkInfo(contexts, name) {
  const run = (contexts || []).find(c => c.__typename === "CheckRun" && c.name === name)
  if (!run) return { status: "none", conclusion: null }
  return { status: run.status?.toLowerCase() || "none", conclusion: run.conclusion?.toLowerCase() || null }
}

function relTime(iso) {
  if (!iso) return "-"
  const ms = Date.now() - new Date(iso).getTime()
  const m = Math.floor(ms / 60000)
  if (m < 60) return m + "m ago"
  const h = Math.floor(m / 60)
  if (h < 24) return h + "h ago"
  return Math.floor(h / 24) + "d ago"
}

const results = rawNodes.map(pr => {
  const repo = pr.repository?.name || REPO
  const n = pr.number
  const sha = pr.headRefOid?.substring(0, 7) || "?"
  const lastCommitNode = pr.commits?.nodes?.[0]?.commit
  const lastCommitDate = lastCommitNode?.committedDate || null
  const contexts = lastCommitNode?.statusCheckRollup?.contexts?.nodes || []

  // Collect review thread comments (inline review comments)
  const reviewThreadComments = []
  for (const thread of (pr.reviewThreads?.nodes || [])) {
    for (const c of (thread.comments?.nodes || [])) {
      if (c.author?.login !== user) {
        reviewThreadComments.push({
          user: c.author?.login,
          body: c.bodyText?.substring(0, 120),
          at: c.createdAt,
          path: c.path,
          line: c.line,
          type: "review"
        })
      }
    }
  }

  // Issue comments
  const issueComments = (pr.comments?.nodes || [])
    .filter(c => c.author?.login !== user)
    .map(c => ({
      user: c.author?.login,
      body: c.bodyText?.substring(0, 120),
      at: c.createdAt,
      type: "issue"
    }))

  const allComments = [...reviewThreadComments, ...issueComments]
    .sort((a, b) => b.at.localeCompare(a.at))

  // Split into new (after last commit) and old
  const newComments = lastCommitDate
    ? allComments.filter(c => c.at > lastCommitDate)
    : []
  const oldComments = lastCommitDate
    ? allComments.filter(c => c.at <= lastCommitDate)
    : allComments

  // Review approval status — dedupe to latest review per human user
  const latestByUser = {}
  for (const r of (pr.reviews?.nodes || [])) {
    const login = r.author?.login
    if (!login || login.endsWith("[bot]")) continue
    if (login === user) continue
    if (!latestByUser[login] || r.submittedAt > latestByUser[login].submittedAt) {
      latestByUser[login] = r
    }
  }
  const approvals = Object.values(latestByUser).filter(r => r.state === "APPROVED").map(r => r.author.login)
  const changesRequested = Object.values(latestByUser).filter(r => r.state === "CHANGES_REQUESTED").map(r => r.author.login)
  const reviewerCount = Object.keys(latestByUser).length

  return {
    number: n,
    repo,
    title: pr.title,
    branch: pr.headRefName,
    draft: pr.isDraft,
    isNew: newPrNumbers.has(n),
    lastCommitSha: sha,
    lastCommitDate,
    comments: {
      total: allComments.length,
      new: newComments.length,
      old: oldComments.length,
      newComments: newComments.map(c => ({ user: c.user, at: c.at, path: c.path, line: c.line, body: c.body })),
      latest: allComments[0] ? { user: allComments[0].user, at: allComments[0].at } : null
    },
    reviews: {
      approvals,
      changesRequested,
      reviewerCount
    },
    checks: {
      bugbot: checkInfo(contexts, "Cursor Bugbot"),
      ci: checkInfo(contexts, "Travis CI - Pull Request"),
      codeql: checkInfo(contexts, "Analyze (javascript-typescript)")
    }
  }
})

// Calculate recommended interval
const secsUntilReset = rlResetAt ? Math.max(1, Math.floor((new Date(rlResetAt).getTime() - Date.now()) / 1000)) : 3600
const budgetCalls = rlRemaining != null ? Math.floor(rlRemaining * BUDGET) : 2500
const pollsAvailable = budgetCalls > 0 ? Math.floor(budgetCalls / rlCost) : 1
const recommendedInterval = Math.max(30, Math.ceil(secsUntilReset / pollsAvailable))

const meta = {
  backend: "graphql",
  queryCost: rlCost,
  rateLimitRemaining: rlRemaining,
  rateLimitLimit: rlLimit,
  rateLimitResetAt: rlResetAt,
  recommendedInterval
}

if (FORMAT === "json") {
  console.log(JSON.stringify({ user, owner: OWNER, repo: REPO || null, timestamp: new Date().toISOString(), meta, prs: results }, null, 2))
  process.exit(0)
}

// Text output — FORCE_COLOR env var overrides TTY detection (for pr-watch subshell)
const IS_TTY = process.env.FORCE_COLOR === "1" || process.stdout.isTTY
const B = IS_TTY ? "\x1b[1m" : ""
const D = IS_TTY ? "\x1b[2m" : ""
const R = IS_TTY ? "\x1b[0m" : ""
const GR = IS_TTY ? "\x1b[32m" : ""
const YL = IS_TTY ? "\x1b[33m" : ""
const RD = IS_TTY ? "\x1b[31m" : ""
const CY = IS_TTY ? "\x1b[36m" : ""
const MG = IS_TTY ? "\x1b[35m" : ""
const LINE = "─".repeat(72)
const multiRepo = !REPO

function fmtCheck(label, c) {
  if (c.status === "none") return D + label + " —" + R
  if (c.status !== "completed") return YL + "⏳ " + label + R
  if (c.conclusion === "success") return GR + "✅ " + label + R
  if (c.conclusion === "neutral") return YL + "⚠️  " + label + R
  if (c.conclusion === "failure") return RD + "❌ " + label + R
  return label + " " + (c.conclusion || "?")
}

function fmtReview(pr) {
  const { approvals, changesRequested, reviewerCount } = pr.reviews
  if (changesRequested.length > 0)
    return `${RD}❌ Changes requested${R} ${D}(${changesRequested.join(", ")})${R}`
  if (approvals.length > 0 && approvals.length >= reviewerCount && reviewerCount > 0)
    return `${GR}✅ Approved${R} ${D}(${approvals.join(", ")})${R}`
  if (approvals.length > 0)
    return `${GR}👍 ${approvals.length}/${reviewerCount} approved${R} ${D}(${approvals.join(", ")})${R}`
  if (reviewerCount > 0)
    return `${YL}👀 Awaiting review${R}`
  return `${D}No reviews${R}`
}

function prState(pr) {
  const hasApproval = pr.reviews.approvals.length > 0
  const hasChangesRequested = pr.reviews.changesRequested.length > 0
  const hasNew = pr.comments.new > 0
  const bugbotOk = pr.checks.bugbot.conclusion === "success" || pr.checks.bugbot.status === "none"
  const ciOk = pr.checks.ci.conclusion === "success" || pr.checks.ci.status === "none"
  const ciFail = pr.checks.ci.conclusion === "failure"
  const ciPending = pr.checks.ci.status !== "completed" && pr.checks.ci.status !== "none"
  const bugbotPending = pr.checks.bugbot.status !== "completed" && pr.checks.bugbot.status !== "none"
  const bugbotIssues = pr.checks.bugbot.conclusion === "neutral"
  const checksGreen = bugbotOk && ciOk

  if (ciFail || hasChangesRequested)
    return { tier: 5, tag: `${RD}${B}BLOCKED${R}`, emoji: "🔴" }
  if (hasNew || bugbotIssues)
    return { tier: 4, tag: `${YL}${B}ATTENTION${R}`, emoji: "🟡" }
  if (ciPending || bugbotPending)
    return { tier: 3, tag: `${YL}PENDING${R}`, emoji: "⏳" }
  if (hasApproval && checksGreen)
    return { tier: 0, tag: `${GR}${B}READY${R}`, emoji: "🚀" }
  if (hasApproval)
    return { tier: 1, tag: `${GR}APPROVED${R}`, emoji: "👍" }
  if (checksGreen)
    return { tier: 2, tag: `${GR}CLEAR${R}`, emoji: "🟢" }
  return { tier: 3, tag: `${D}OPEN${R}`, emoji: "⚪" }
}

function sortedPRs(list) {
  return [...list].sort((a, b) => {
    const ta = prState(a).tier, tb = prState(b).tier
    if (ta !== tb) return ta - tb
    const da = a.comments.latest?.at || a.lastCommitDate || ""
    const db = b.comments.latest?.at || b.lastCommitDate || ""
    return db.localeCompare(da)
  })
}

function renderPR(pr, indent) {
  const state = prState(pr)
  const draft = pr.draft ? ` ${D}[draft]${R}` : ""
  const newPrTag = pr.isNew ? ` ${MG}${B}NEW${R}` : ""
  const title = pr.title.length > 45 ? pr.title.substring(0, 42) + "..." : pr.title
  const newTag = pr.comments.new > 0
    ? `  ${RD}${B}🔔 +${pr.comments.new} new${R}`
    : ""
  const latestInfo = pr.comments.latest
    ? `${D}${pr.comments.latest.user} ${relTime(pr.comments.latest.at)}${R}`
    : `${D}none${R}`
  const pad = " ".repeat(indent)
  const prUrl = `https://github.com/${OWNER}/${pr.repo}/pull/${pr.number}`

  const lines = []
  lines.push(`${pad}${state.emoji} ${state.tag}  ${B}#${pr.number}${R}${draft}${newPrTag} ${CY}${title}${R}`)
  lines.push(`${pad}   ${D}↳${R} ${MG}${pr.branch}${R}  ${D}${prUrl}${R}`)
  lines.push(`${pad}   ${fmtReview(pr)}`)
  lines.push(`${pad}   💬 ${pr.comments.total}${newTag}  ${D}latest:${R} ${latestInfo}`)
  lines.push(`${pad}   ${fmtCheck("Bugbot", pr.checks.bugbot)}  ${fmtCheck("CI", pr.checks.ci)}  ${fmtCheck("CodeQL", pr.checks.codeql)}`)
  return lines
}

const scope = REPO ? `${OWNER}/${REPO}` : `${OWNER}/*`
const out = []
out.push(`${B}${scope}${R} ${D}— ${user} — ${results.length} open PR(s)${R}`)
out.push(`${D}${LINE}${R}`)

if (!results.length) {
  out.push(`${D}No open PRs by ${user}${R}`)
} else if (multiRepo) {
  const byRepo = {}
  for (const pr of results) {
    if (!byRepo[pr.repo]) byRepo[pr.repo] = []
    byRepo[pr.repo].push(pr)
  }
  const repoOrder = Object.keys(byRepo).sort((a, b) => {
    const latestA = sortedPRs(byRepo[a])[0]
    const latestB = sortedPRs(byRepo[b])[0]
    const da = latestA.comments.latest?.at || latestA.lastCommitDate || ""
    const db = latestB.comments.latest?.at || latestB.lastCommitDate || ""
    return db.localeCompare(da)
  })
  for (const repo of repoOrder) {
    out.push(``)
    out.push(`${B}${repo}${R} ${D}(${byRepo[repo].length})${R}`)
    for (const pr of sortedPRs(byRepo[repo])) {
      out.push("")
      out.push(...renderPR(pr, 2))
    }
  }
} else {
  for (const pr of sortedPRs(results)) {
    out.push("")
    out.push(...renderPR(pr, 0))
  }
}

// Footer with rate limit info
out.push("")
const rlInfo = rlRemaining != null
  ? `GQL: ${rlRemaining}/${rlLimit} remaining (cost ${rlCost})`
  : "GQL: unknown"
out.push(`${D}${LINE}${R}`)
out.push(`${D}${rlInfo}  |  next: ${recommendedInterval}s${R}`)

// Machine-readable line for pr-watch.sh to parse
out.push(`# interval:${recommendedInterval}`)

console.log(out.join("\n"))
' "$OWNER" "$REPO" "$USER" "$FORMAT" "$BUDGET" "$STATE_DIR" "$GQL_RESULT"
