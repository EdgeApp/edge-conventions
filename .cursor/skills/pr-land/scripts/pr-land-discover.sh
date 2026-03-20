#!/usr/bin/env node
// pr-land-discover.sh — Discovers all user's open PRs across EdgeApp repos
// with approval status using a single GraphQL query.
//
// Usage: ./pr-land-discover.sh [repo1] [repo2] ...
// Example: ./pr-land-discover.sh edge-react-gui edge-core-js
// Example: ./pr-land-discover.sh  (no args = all EdgeApp repos)

const { spawnSync } = require("child_process");

const specifiedRepos = process.argv.slice(2);
const edgeAppRepos = [
  "edge-react-gui",
  "edge-exchange-plugins",
  "edge-currency-accountbased",
  "edge-core-js",
  "edge-login-ui-rn",
  "edge-currency-plugins",
];
const repos = specifiedRepos.length > 0 ? specifiedRepos : edgeAppRepos;

function requireGh() {
  const check = spawnSync("gh", ["auth", "status"], { encoding: "utf8" });
  if (check.status !== 0) {
    console.error("PROMPT_GH_AUTH");
    process.exit(2);
  }
}

function ghGraphql(query, variables = {}) {
  const args = ["api", "graphql", "-f", `query=${query}`];
  for (const [k, v] of Object.entries(variables)) {
    args.push(typeof v === "number" ? "-F" : "-f", `${k}=${v}`);
  }
  const result = spawnSync("gh", args, { encoding: "utf8" });
  if (result.status !== 0) {
    throw new Error(`GraphQL failed: ${(result.stderr || "").trim()}`);
  }
  const parsed = JSON.parse(result.stdout);
  if (parsed.errors) {
    throw new Error(`GraphQL errors: ${JSON.stringify(parsed.errors)}`);
  }
  return parsed.data;
}

requireGh();

// Build a single GraphQL query with aliases for all repos.
// Each alias fetches open PRs + latest review state in one round-trip.
const repoFragments = repos
  .map((repo, i) => {
    const alias = `repo${i}`;
    return `${alias}: repository(owner: "EdgeApp", name: "${repo}") {
    name
    pullRequests(first: 100, states: OPEN) {
      nodes {
        number
        title
        headRefName
        updatedAt
        reviews(last: 30) {
          nodes {
            author { login }
            state
            submittedAt
          }
        }
      }
    }
  }`;
  })
  .join("\n  ");

const query = `{ ${repoFragments} }`;

let data;
try {
  data = ghGraphql(query);
} catch (e) {
  console.error("ERROR:", e.message);
  process.exit(1);
}

const results = { prs: [], errors: [] };

for (const key of Object.keys(data)) {
  const repoData = data[key];
  if (!repoData) continue;
  const repo = repoData.name;

  for (const pr of repoData.pullRequests.nodes) {
    if (!pr.headRefName.startsWith("jon/")) continue;

    // Dedupe reviews: keep latest per reviewer
    const latestByUser = {};
    for (const r of pr.reviews.nodes) {
      const login = r.author?.login;
      if (!login) continue;
      if (
        !latestByUser[login] ||
        new Date(r.submittedAt) > new Date(latestByUser[login].submittedAt)
      ) {
        latestByUser[login] = r;
      }
    }

    const reviewers = Object.values(latestByUser);
    const approved = reviewers.some((r) => r.state === "APPROVED");
    const changesRequested = reviewers.some(
      (r) => r.state === "CHANGES_REQUESTED"
    );

    results.prs.push({
      repo,
      prNumber: pr.number,
      branch: pr.headRefName,
      title: pr.title,
      updatedAt: pr.updatedAt,
      approved,
      changesRequested,
      reviewers: reviewers.map((r) => ({
        user: r.author.login,
        state: r.state,
      })),
    });
  }
}

results.prs.sort(
  (a, b) => a.repo.localeCompare(b.repo) || a.branch.localeCompare(b.branch)
);
console.log(JSON.stringify(results, null, 2));
