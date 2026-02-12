#!/usr/bin/env node
// pr-land-comments.sh — Checks for recent comments (after last commit) on PRs.
// Uses a single GraphQL query per PR instead of 3 REST calls.
//
// Usage: echo '[{"repo":"edge-react-gui","prNumber":123,"branch":"jon/feature"}]' | ./pr-land-comments.sh

const { spawnSync } = require("child_process");

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

const QUERY = `
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      commits(last: 1) {
        nodes { commit { committedDate } }
      }
      reviewThreads(first: 100) {
        nodes {
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
      comments(last: 50) {
        nodes {
          createdAt
          author { login }
          body
        }
      }
    }
  }
}`;

requireGh();

async function main() {
  let input = "";
  for await (const chunk of process.stdin) {
    input += chunk;
  }

  const prs = JSON.parse(input);
  const results = [];

  for (const { repo, prNumber, branch } of prs) {
    let data;
    try {
      data = ghGraphql(QUERY, {
        owner: "EdgeApp",
        repo,
        number: prNumber,
      });
    } catch (e) {
      console.error(`WARNING: Failed to query ${repo}#${prNumber}: ${e.message}`);
      continue;
    }

    const pr = data.repository.pullRequest;
    const lastCommitNode = pr.commits.nodes[0];
    const lastCommitDate = lastCommitNode
      ? new Date(lastCommitNode.commit.committedDate)
      : new Date(0);

    const recentComments = [];

    // Inline review comments from threads
    for (const thread of pr.reviewThreads.nodes) {
      for (const c of thread.comments.nodes) {
        if (new Date(c.createdAt) > lastCommitDate) {
          recentComments.push({
            type: "inline",
            user: c.author?.login,
            path: c.path,
            body: c.body?.slice(0, 100),
          });
        }
      }
    }

    // Top-level issue comments
    for (const c of pr.comments.nodes) {
      if (new Date(c.createdAt) > lastCommitDate) {
        recentComments.push({
          type: "top-level",
          user: c.author?.login,
          body: c.body?.slice(0, 100),
        });
      }
    }

    if (recentComments.length > 0) {
      results.push({ repo, prNumber, branch, recentComments });
    }
  }

  console.log(JSON.stringify(results, null, 2));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
