#!/usr/bin/env node
// pr-land-comments.sh — Landing gate: checks for recent unaddressed feedback.
// Surfaces unresolved inline threads, review bodies, and top-level comments
// posted after the last commit. Uses a single GraphQL query per PR.
//
// Skips: resolved threads, bot/author comments, items with addressed markers.
//
// Usage: echo '[{"repo":"...","prNumber":123,"branch":"..."}]' | ./pr-land-comments.sh

const { spawnSync } = require("child_process")

function requireGh() {
  const check = spawnSync("gh", ["auth", "status"], { encoding: "utf8" })
  if (check.status !== 0) {
    console.error("PROMPT_GH_AUTH")
    process.exit(2)
  }
}

function ghGraphql(query, variables = {}) {
  const args = ["api", "graphql", "-f", `query=${query}`]
  for (const [k, v] of Object.entries(variables)) {
    args.push(typeof v === "number" ? "-F" : "-f", `${k}=${v}`)
  }
  const result = spawnSync("gh", args, { encoding: "utf8" })
  if (result.status !== 0) {
    throw new Error(`GraphQL failed: ${(result.stderr || "").trim()}`)
  }
  const parsed = JSON.parse(result.stdout)
  if (parsed.errors) {
    throw new Error(`GraphQL errors: ${JSON.stringify(parsed.errors)}`)
  }
  return parsed.data
}

const QUERY = `
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      author { login }
      commits(last: 1) {
        nodes { commit { committedDate } }
      }
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          comments(first: 50) {
            nodes {
              createdAt
              author { login }
              path
              body
            }
          }
        }
      }
      reviews(last: 50) {
        nodes {
          databaseId
          author { login }
          state
          body
          submittedAt
        }
      }
      comments(last: 50) {
        nodes {
          databaseId
          createdAt
          author { login }
          body
        }
      }
    }
  }
}`

requireGh()

function extractAddressedIds(comments) {
  const ids = new Set()
  for (const c of comments) {
    for (const m of (c.body || "").matchAll(
      /<!-- addressed:(?:review|comment):(\d+) -->/g
    )) {
      ids.add(Number(m[1]))
    }
  }
  return ids
}

function isBot(login) {
  return !login || login.includes("[bot]")
}

async function main() {
  let input = ""
  for await (const chunk of process.stdin) input += chunk

  const prs = JSON.parse(input)
  const results = []

  for (const { repo, prNumber, branch } of prs) {
    let data
    try {
      data = ghGraphql(QUERY, { owner: "EdgeApp", repo, number: prNumber })
    } catch (e) {
      console.error(
        `WARNING: Failed to query ${repo}#${prNumber}: ${e.message}`
      )
      continue
    }

    const pr = data.repository.pullRequest
    const prAuthor = pr.author?.login
    const lastCommitDate = pr.commits.nodes[0]
      ? new Date(pr.commits.nodes[0].commit.committedDate)
      : new Date(0)

    const addressedIds = extractAddressedIds(pr.comments.nodes)
    const recentComments = []

    for (const thread of pr.reviewThreads.nodes) {
      if (thread.isResolved) continue
      for (const c of thread.comments.nodes) {
        if (new Date(c.createdAt) > lastCommitDate) {
          recentComments.push({
            type: "inline",
            user: c.author?.login,
            path: c.path,
            body: c.body?.slice(0, 200)
          })
        }
      }
    }

    const latestByUser = {}
    for (const r of pr.reviews.nodes) {
      const user = r.author?.login
      if (!user || user === prAuthor || r.state === "PENDING") continue
      if (isBot(user)) continue
      const prev = latestByUser[user]
      if (
        !prev ||
        new Date(r.submittedAt) > new Date(prev.submittedAt)
      ) {
        latestByUser[user] = r
      }
    }
    for (const [user, r] of Object.entries(latestByUser)) {
      if (!r.body?.trim()) continue
      if (addressedIds.has(r.databaseId)) continue
      if (new Date(r.submittedAt) > lastCommitDate) {
        recentComments.push({
          type: "review-body",
          user,
          state: r.state,
          body: r.body.slice(0, 200)
        })
      }
    }

    for (const c of pr.comments.nodes) {
      const user = c.author?.login
      if (!user || user === prAuthor || isBot(user)) continue
      if ((c.body || "").includes("<!-- addressed:")) continue
      if (addressedIds.has(c.databaseId)) continue
      if (new Date(c.createdAt) > lastCommitDate) {
        recentComments.push({
          type: "top-level",
          user,
          body: c.body?.slice(0, 200)
        })
      }
    }

    if (recentComments.length > 0) {
      results.push({ repo, prNumber, branch, recentComments })
    }
  }

  console.log(JSON.stringify(results, null, 2))
}

main().catch(e => {
  console.error(e)
  process.exit(1)
})
