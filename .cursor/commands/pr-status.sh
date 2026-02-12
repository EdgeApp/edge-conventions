#!/usr/bin/env bash
# pr-status.sh — Fetch status of open PRs for a user (REST API).
# Single run, no TUI. "New" comments = posted after the PR's last commit.
#
# Rate-limit aware:
#   - ETag caching (304 = free, no quota cost)
#   - Per-PR updated_at diffing (skip detail fetches for unchanged PRs)
#   - Tracks X-RateLimit-Remaining, outputs footer + recommended interval
#
# Usage:
#   pr-status.sh --repo edge-react-gui [--owner EdgeApp] [--user Jon-edge] [--format text|json]
#   pr-status.sh                       # All repos for user in EdgeApp org
#   pr-status.sh --user Jon-edge       # All repos for specific user in EdgeApp org
#   pr-status.sh --budget 0.5          # Reserve 50% of rate limit for other tools
#
# Requires: GITHUB_TOKEN env var, node.
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

[[ -z "${GITHUB_TOKEN:-}" ]] && { echo "Error: GITHUB_TOKEN not set." >&2; exit 2; }

STATE_DIR="${TMPDIR:-/tmp}/pr-watch-${OWNER}-${REPO:-all}"
mkdir -p "$STATE_DIR"
export STATE_DIR

exec node -e '
const https = require("https")
const fs = require("fs")
const crypto = require("crypto")
const { OWNER, REPO, USER, FORMAT, BUDGET } = {
  OWNER: process.argv[1],
  REPO: process.argv[2] || "",
  USER: process.argv[3],
  FORMAT: process.argv[4],
  BUDGET: parseFloat(process.argv[5]) || 0.67
}
const TOKEN = process.env.GITHUB_TOKEN
const STATE_DIR = process.env.STATE_DIR

// --- Rate limit tracking ---
let rateLimitRemaining = null
let rateLimitLimit = null
let rateLimitReset = null
let apiCallCount = 0
let cacheHitCount = 0

// --- ETag + body caching ---
function cacheKey(path) {
  return crypto.createHash("md5").update(path).digest("hex").substring(0, 12)
}

function loadEtag(path) {
  try { return fs.readFileSync(`${STATE_DIR}/etag-${cacheKey(path)}`, "utf8").trim() } catch { return null }
}

function saveEtag(path, etag) {
  if (etag) fs.writeFileSync(`${STATE_DIR}/etag-${cacheKey(path)}`, etag)
}

function loadCachedBody(path) {
  try { return JSON.parse(fs.readFileSync(`${STATE_DIR}/body-${cacheKey(path)}.json`, "utf8")) } catch { return null }
}

function saveCachedBody(path, body) {
  fs.writeFileSync(`${STATE_DIR}/body-${cacheKey(path)}.json`, JSON.stringify(body))
}

function ghFetch(path) {
  return new Promise((resolve, reject) => {
    const headers = {
      Authorization: `Bearer ${TOKEN}`,
      Accept: "application/vnd.github+json",
      "User-Agent": "pr-status"
    }
    const etag = loadEtag(path)
    if (etag) headers["If-None-Match"] = etag

    https.get({ hostname: "api.github.com", path, headers }, res => {
      // Track rate limit from every response
      const rl = res.headers["x-ratelimit-remaining"]
      const rlLimit = res.headers["x-ratelimit-limit"]
      const rlReset = res.headers["x-ratelimit-reset"]
      if (rl != null) rateLimitRemaining = Math.min(rateLimitRemaining ?? Infinity, parseInt(rl, 10))
      if (rlLimit != null) rateLimitLimit = parseInt(rlLimit, 10)
      if (rlReset != null) rateLimitReset = parseInt(rlReset, 10)

      if (res.statusCode === 304) {
        cacheHitCount++
        const cached = loadCachedBody(path)
        resolve(cached)
        return
      }

      apiCallCount++
      let data = ""
      res.on("data", c => (data += c))
      res.on("end", () => {
        const newEtag = res.headers["etag"]
        saveEtag(path, newEtag)
        try {
          const body = JSON.parse(data)
          saveCachedBody(path, body)
          resolve(body)
        } catch { resolve(null) }
      })
    }).on("error", reject)
  })
}

// --- Per-PR updated_at caching ---
function loadPrCache(number) {
  try { return JSON.parse(fs.readFileSync(`${STATE_DIR}/pr-${number}.json`, "utf8")) } catch { return null }
}

function savePrCache(number, result, updatedAt) {
  fs.writeFileSync(`${STATE_DIR}/pr-${number}.json`, JSON.stringify({ updatedAt, result }))
}

function loadPreviousPrNumbers() {
  try { return JSON.parse(fs.readFileSync(`${STATE_DIR}/known-prs.json`, "utf8")) } catch { return [] }
}

function savePrNumbers(numbers) {
  fs.writeFileSync(`${STATE_DIR}/known-prs.json`, JSON.stringify(numbers))
}

// --- Utilities ---
function relTime(iso) {
  if (!iso) return "-"
  const ms = Date.now() - new Date(iso).getTime()
  const m = Math.floor(ms / 60000)
  if (m < 60) return m + "m ago"
  const h = Math.floor(m / 60)
  if (h < 24) return h + "h ago"
  return Math.floor(h / 24) + "d ago"
}

function checkInfo(runs, name) {
  const run = (runs || []).find(c => c.name === name)
  if (!run) return { status: "none", conclusion: null }
  return { status: run.status, conclusion: run.conclusion }
}

async function main() {
  let user = USER
  if (!user) {
    const me = await ghFetch("/user")
    user = me?.login || "unknown"
  }

  const previousPrNumbers = loadPreviousPrNumbers()

  // Collect PRs: either from one repo or search across org
  let prs
  if (REPO) {
    const allPRs = await ghFetch(`/repos/${OWNER}/${REPO}/pulls?state=open&per_page=30`)
    if (!Array.isArray(allPRs)) {
      process.stderr.write("API error fetching PRs\n")
      process.exit(1)
    }
    prs = allPRs
      .filter(p => p.user.login === user)
      .map(p => ({ ...p, _repo: REPO }))
  } else {
    // Search all repos in org for open PRs by user
    const q = encodeURIComponent(`type:pr state:open author:${user} org:${OWNER}`)
    const search = await ghFetch(`/search/issues?q=${q}&per_page=50&sort=updated&order=desc`)
    if (!search?.items) {
      process.stderr.write("API error searching PRs\n")
      process.exit(1)
    }
    // Search results lack head sha; fetch full PR objects
    prs = await Promise.all(search.items.map(async item => {
      const repo = item.repository_url.split("/").pop()
      const full = await ghFetch(`/repos/${OWNER}/${repo}/pulls/${item.number}`)
      return { ...full, _repo: repo }
    }))
  }

  // Track which PRs are new
  const currentPrNumbers = prs.map(p => p.number)
  const newPrNumbers = new Set(currentPrNumbers.filter(n => !previousPrNumbers.includes(n)))
  savePrNumbers(currentPrNumbers)

  let changedPrCount = 0

  const results = await Promise.all(prs.map(async pr => {
    const repo = pr._repo
    const n = pr.number
    const sha = pr.head.sha
    const updatedAt = pr.updated_at

    // Check if PR has changed since last poll
    const cached = loadPrCache(n)
    if (cached && cached.updatedAt === updatedAt && !newPrNumbers.has(n)) {
      // Unchanged — use cached result, but update isNew flag
      return { ...cached.result, isNew: false }
    }

    changedPrCount++

    // Fetch in parallel: inline comments, issue comments, check runs, commits, reviews
    const [inline, issue, checks, commits, reviews] = await Promise.all([
      ghFetch(`/repos/${OWNER}/${repo}/pulls/${n}/comments?per_page=100`),
      ghFetch(`/repos/${OWNER}/${repo}/issues/${n}/comments?per_page=100`),
      ghFetch(`/repos/${OWNER}/${repo}/commits/${sha}/check-runs`),
      ghFetch(`/repos/${OWNER}/${repo}/pulls/${n}/commits?per_page=100`),
      ghFetch(`/repos/${OWNER}/${repo}/pulls/${n}/reviews?per_page=100`)
    ])

    // Last commit timestamp
    const commitList = Array.isArray(commits) ? commits : []
    const lastCommit = commitList.length > 0 ? commitList[commitList.length - 1] : null
    const lastCommitDate = lastCommit?.commit?.committer?.date
      || lastCommit?.commit?.author?.date
      || null

    // All comments by others
    const allComments = [
      ...(Array.isArray(inline) ? inline : [])
        .filter(c => c.user?.login !== user)
        .map(c => ({ id: c.id, user: c.user?.login, body: c.body?.substring(0, 120), at: c.created_at, path: c.path, line: c.line, type: "review" })),
      ...(Array.isArray(issue) ? issue : [])
        .filter(c => c.user?.login !== user)
        .map(c => ({ id: c.id, user: c.user?.login, body: c.body?.substring(0, 120), at: c.created_at, type: "issue" }))
    ].sort((a, b) => b.at.localeCompare(a.at))

    // Split into new (after last commit) and old
    const newComments = lastCommitDate
      ? allComments.filter(c => c.at > lastCommitDate)
      : []
    const oldComments = lastCommitDate
      ? allComments.filter(c => c.at <= lastCommitDate)
      : allComments

    const checkRuns = checks?.check_runs || []

    // Review approval status — dedupe to latest review per human user
    const reviewList = Array.isArray(reviews) ? reviews : []
    const latestByUser = {}
    for (const r of reviewList) {
      const login = r.user?.login
      if (!login || login.endsWith("[bot]")) continue
      if (login === user) continue
      if (!latestByUser[login] || r.submitted_at > latestByUser[login].submitted_at) {
        latestByUser[login] = r
      }
    }
    const approvals = Object.values(latestByUser).filter(r => r.state === "APPROVED").map(r => r.user.login)
    const changesRequested = Object.values(latestByUser).filter(r => r.state === "CHANGES_REQUESTED").map(r => r.user.login)
    const reviewerCount = Object.keys(latestByUser).length

    const result = {
      number: n,
      repo,
      title: pr.title,
      branch: pr.head.ref,
      draft: pr.draft,
      isNew: newPrNumbers.has(n),
      lastCommitSha: sha.substring(0, 7),
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
        bugbot: checkInfo(checkRuns, "Cursor Bugbot"),
        ci: checkInfo(checkRuns, "Travis CI - Pull Request"),
        codeql: checkInfo(checkRuns, "Analyze (javascript-typescript)")
      }
    }

    savePrCache(n, result, updatedAt)
    return result
  }))

  // Calculate recommended interval
  const callsPerPoll = 1 + (changedPrCount > 0 ? changedPrCount * 5 : prs.length * 5)
  const secsUntilReset = rateLimitReset ? Math.max(1, rateLimitReset - Math.floor(Date.now() / 1000)) : 3600
  const budgetCalls = rateLimitRemaining != null ? Math.floor(rateLimitRemaining * BUDGET) : 2500
  const recommendedInterval = budgetCalls > 0 ? Math.max(30, Math.ceil(secsUntilReset / (budgetCalls / callsPerPoll))) : 300

  const meta = {
    apiCalls: apiCallCount,
    cacheHits: cacheHitCount,
    changedPrs: changedPrCount,
    rateLimitRemaining,
    rateLimitLimit,
    rateLimitReset,
    recommendedInterval
  }

  if (FORMAT === "json") {
    console.log(JSON.stringify({ user, owner: OWNER, repo: REPO || null, timestamp: new Date().toISOString(), meta, prs: results }, null, 2))
    return
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
  const rlInfo = rateLimitRemaining != null
    ? `API: ${rateLimitRemaining}/${rateLimitLimit} remaining`
    : "API: unknown"
  const cacheInfo = `${apiCallCount} calls, ${cacheHitCount} cached`
  out.push(`${D}${LINE}${R}`)
  out.push(`${D}${rlInfo}  |  ${cacheInfo}  |  next: ${recommendedInterval}s${R}`)

  // Machine-readable line for pr-watch.sh to parse
  out.push(`# interval:${recommendedInterval}`)

  console.log(out.join("\n"))
}

main().catch(e => { process.stderr.write("Error: " + e.message + "\n"); process.exit(1) })
' "$OWNER" "$REPO" "$USER" "$FORMAT" "$BUDGET"
