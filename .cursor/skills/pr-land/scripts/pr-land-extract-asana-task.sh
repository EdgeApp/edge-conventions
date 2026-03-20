#!/usr/bin/env node
// pr-land-extract-asana-task.sh
// Extracts Asana task GIDs from PR bodies so /pr-land can skip loading full descriptions.
// Input: JSON array of {repo, prNumber}. Output: JSON object {tasks: [...], missing: [...]}, where each entry contains label/repo info.
//
// The script is intentionally terse: it only emits structured JSON and does not print raw PR bodies.
const { execSync } = require("child_process");
const path = require("path");

async function readStdin() {
  let input = "";
  for await (const chunk of process.stdin) {
    input += chunk;
  }
  return input.trim();
}

function fetchPrBody(repo, prNumber) {
  const endpoint = `repos/EdgeApp/${repo}/pulls/${prNumber}`;
  const result = execSync(`gh api "${endpoint}" --jq '.body'`, {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
  return result.trim();
}

function buildLabel(repo, prNumber) {
  return `${repo}#${prNumber}`;
}

async function main() {
  const input = await readStdin();
  if (!input) {
    console.error("Error: no input received (expecting JSON array with repo/prNumber)");
    process.exit(2);
  }

  let entries;
  try {
    entries = JSON.parse(input);
  } catch (err) {
    console.error("Error: failed to parse JSON input");
    process.exit(2);
  }

  const regex = /https:\/\/app\.asana\.com\/\d+\/\d+\/(?:task\/)?(\d+)/i;
  const tasks = [];
  const missing = [];

  for (const { repo, prNumber } of entries) {
    const label = buildLabel(repo, prNumber);
    let body;
    try {
      body = fetchPrBody(repo, prNumber);
    } catch (err) {
      missing.push({
        label,
        reason: `Failed to fetch PR body: ${err.message}`,
      });
      continue;
    }

    if (!body) {
      missing.push({
        label,
        reason: "PR body empty",
      });
      continue;
    }

    const match = body.match(regex);
    if (match) {
      tasks.push({
        taskGid: match[1],
        label,
      });
    } else {
      missing.push({
        label,
        reason: "No Asana link found",
      });
    }
  }

  console.log(JSON.stringify({ tasks, missing }, null, 2));
  process.exit(0);
}

main().catch((err) => {
  console.error(`Error: ${err.message}`);
  process.exit(1);
});
