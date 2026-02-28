#!/usr/bin/env node
// pr-land-merge.sh
// Merges PRs via GitHub API with automatic rebase and MANDATORY local verification.
// Uses gh CLI for API calls and edge-repo.js for shared utilities.
//
// Usage: echo '[{"repo":"edge-react-gui","prNumber":123,"branch":"jon/feature"}]' | ./pr-land-merge.sh [method]
// Methods: merge (default), squash, rebase
//
// For each PR (sequentially):
//   1. Check if already merged (skip if so — handles re-runs)
//   2. Fetch + rebase onto latest upstream (picks up prior merges)
//   3. Push --force-with-lease
//   4. Run local verification (MANDATORY)
//   5. Merge via GitHub API
//
// SAFETY GUARANTEES:
//   1. Each PR is rebased onto latest upstream before merge (handles sequential merges)
//   2. Verification runs before EVERY merge (no bypass)
//   3. Code conflicts → Skip PR, continue with remaining
//   4. CHANGELOG-only conflicts → Agent can resolve, then re-run
//   5. Already-merged PRs are detected and skipped on re-runs
//
// Exit codes:
//   0 = All (non-skipped) PRs merged successfully
//   1 = Verification failed
//   4 = CHANGELOG-only conflict (agent can resolve semantically)

const { spawnSync } = require("child_process");
const path = require("path");
const {
  getRepoDir,
  getUpstreamBranch,
  runGit,
  parseConflictFiles,
  isChangelogOnly,
  runVerification,
  ghApi,
  installAndPrepare,
} = require(path.join(__dirname, "edge-repo.js"));

function sanitizeBranchLabel(branch) {
  return branch.replace(/[^a-z0-9]/gi, "-").replace(/-+/g, "-").replace(/^-|-$/g, "");
}

function describeBranchState(repoDir, branch) {
  const notes = [];
  const local = runGit(["rev-parse", branch], repoDir, { allowFailure: true });
  notes.push(local.success ? `Local commit (${branch}): ${local.stdout}` : `Local branch "${branch}" missing`);

  const remote = runGit(["rev-parse", `origin/${branch}`], repoDir, { allowFailure: true });
  notes.push(remote.success ? `Remote commit (origin/${branch}): ${remote.stdout}` : `Remote branch origin/${branch} missing`);

  const status = runGit(["status", "-sb"], repoDir, { allowFailure: true });
  if (status.stdout) {
    notes.push(`Status: ${status.stdout.trim()}`);
  }
  return notes.join("\n");
}

function fetchBranchForPush(repoDir, branch) {
  runGit(["fetch", "origin", branch], repoDir, { allowFailure: true });
}

// Verify gh auth
const authCheck = spawnSync("gh", ["auth", "status"], { encoding: "utf8" });
if (authCheck.status !== 0) {
  console.error("PROMPT_GH_AUTH");
  process.exit(2);
}

const mergeMethod = process.argv[2] || "merge";
if (!["merge", "squash", "rebase"].includes(mergeMethod)) {
  console.error("ERROR: Invalid merge method. Use: merge, squash, or rebase");
  process.exit(1);
}

// --- Core functions ---

/**
 * Rebase a branch onto the latest upstream.
 * Returns: { status, conflictFiles? }
 *   status: "success" | "changelog_conflict" | "code_conflict" | "error"
 *
 * On changelog_conflict, the rebase is LEFT IN PROGRESS for agent resolution.
 * On all other failures, the rebase is aborted to leave the repo clean.
 */
function rebaseOntoUpstream(repoDir, branch, repo) {
  const upstream = getUpstreamBranch(repo);

  runGit(["fetch", "origin"], repoDir);

  try {
    runGit(["checkout", branch], repoDir);
  } catch (e) {
    return { status: "error", message: `Checkout failed: ${e.message}` };
  }

  const rebaseResult = runGit(["rebase", upstream], repoDir, {
    allowFailure: true,
  });

  if (rebaseResult.success) {
    return { status: "success" };
  }

  // Conflict detected — analyze
  const combinedOutput = rebaseResult.stdout + "\n" + rebaseResult.stderr;
  let conflictFiles = parseConflictFiles(combinedOutput);

  if (conflictFiles.length === 0) {
    try {
      const statusResult = runGit(["status", "--porcelain"], repoDir, {
        allowFailure: true,
      });
      for (const line of statusResult.stdout.split("\n")) {
        if (line.startsWith("UU ") || line.startsWith("AA ")) {
          conflictFiles.push(line.slice(3).trim());
        }
      }
    } catch {}
  }

  if (conflictFiles.some((f) => !f.includes("CHANGELOG"))) {
    runGit(["rebase", "--abort"], repoDir, { allowFailure: true });
    return { status: "code_conflict", conflictFiles };
  }

  if (isChangelogOnly(conflictFiles)) {
    return { status: "changelog_conflict", conflictFiles };
  }

  runGit(["rebase", "--abort"], repoDir, { allowFailure: true });
  return { status: "error", message: "Unknown conflict type", conflictFiles };
}

function checkPRStatus(repo, prNumber) {
  try {
    const data = ghApi(`repos/EdgeApp/${repo}/pulls/${prNumber}`);
    return {
      state: data.state,
      merged: data.merged || false,
      mergeable: data.mergeable,
      mergeable_state: data.mergeable_state,
    };
  } catch (e) {
    return { error: `Failed to fetch PR status: ${e.message}` };
  }
}

function mergePR(repo, prNumber, branch) {
  const commitTitle = `Merge pull request #${prNumber} from EdgeApp/${branch}`;

  try {
    const data = ghApi(`repos/EdgeApp/${repo}/pulls/${prNumber}/merge`, {
      method: "PUT",
      body: {
        merge_method: mergeMethod,
        commit_title: mergeMethod === "merge" ? commitTitle : undefined,
      },
    });
    return {
      repo,
      prNumber,
      branch,
      success: data?.merged || false,
      merged: data?.merged || false,
      message: data?.message,
      sha: data?.sha,
    };
  } catch (e) {
    return {
      repo,
      prNumber,
      branch,
      success: false,
      merged: false,
      message: e.message,
    };
  }
}

// --- Main ---

async function main() {
  let input = "";
  for await (const chunk of process.stdin) {
    input += chunk;
  }

  const prs = JSON.parse(input);
  const results = {
    merged: [],
    failed: [],
    skipped: [],
    pending: [],
    verificationFailed: null,
    changelogConflict: null,
    conflict: null,
    method: mergeMethod,
    status: "complete",
  };

  let exitCode = 0;

  for (let i = 0; i < prs.length; i++) {
    const { repo, prNumber, branch } = prs[i];
    const repoDir = getRepoDir(repo);

    console.error(
      `\n=== Merging ${repo}#${prNumber} (${branch}) [${i + 1}/${prs.length}] ===`
    );

    // CHECK: Is PR already merged?
    const prStatus = checkPRStatus(repo, prNumber);
    if (prStatus.merged) {
      console.error("✓ Already merged — skipping");
      results.merged.push({
        repo,
        prNumber,
        branch,
        success: true,
        merged: true,
        sha: "already-merged",
        message: "Already merged",
      });
      continue;
    }

    // STEP 1: Rebase onto latest upstream
    console.error("Rebasing onto latest upstream...");
    const rebaseResult = rebaseOntoUpstream(repoDir, branch, repo);

    if (rebaseResult.status === "changelog_conflict") {
      console.error("\n=== CHANGELOG conflict — agent resolution needed ===");
      console.error(`Files: ${rebaseResult.conflictFiles.join(", ")}`);
      console.error("\nTo resolve:");
      console.error(
        `  1. Read ${path.join(repoDir, "CHANGELOG.md")} with conflict markers`
      );
      console.error(
        "  2. Resolve semantically (upstream entries first, then ours)"
      );
      console.error("  3. git add CHANGELOG.md && git rebase --continue");
      console.error("  4. git push --force-with-lease");
      console.error("  5. Re-run merge");
      results.changelogConflict = {
        repo,
        prNumber,
        branch,
        repoDir,
        conflictFiles: rebaseResult.conflictFiles,
      };
      results.status = "changelog_conflict_needs_resolution";
      results.pending = prs.slice(i + 1);
      exitCode = 4;
      break;
    }

    if (rebaseResult.status === "code_conflict") {
      console.error(`⚠ Code conflict — skipping`);
      console.error(
        `  Conflicting files: ${rebaseResult.conflictFiles.join(", ")}`
      );
      results.skipped.push({
        repo,
        prNumber,
        branch,
        repoDir,
        reason: "Code conflict",
        conflictFiles: rebaseResult.conflictFiles,
      });
      continue;
    }

    if (rebaseResult.status !== "success") {
      console.error(
        `⚠ Rebase failed: ${rebaseResult.message || rebaseResult.status} — skipping`
      );
      results.skipped.push({
        repo,
        prNumber,
        branch,
        repoDir,
        reason: `Rebase failed: ${rebaseResult.message || rebaseResult.status}`,
      });
      continue;
    }

    console.error("✓ Rebase complete");

    // STEP 1b: Install dependencies and prepare after rebase
    try {
      installAndPrepare(repoDir);
    } catch (e) {
      console.error(`✗ Dependency install failed: ${e.message}`);
      results.failed.push({
        repo,
        prNumber,
        branch,
        success: false,
        message: `Dependency install failed: ${e.message}`,
      });
      continue;
    }

    // STEP 2: Push rebased branch
    console.error("Pushing rebased branch...");
    const pushResult = runGit(
      ["push", "--force-with-lease", "origin", branch],
      repoDir,
      { allowFailure: true }
    );
    if (!pushResult.success) {
      fetchBranchForPush(repoDir, branch);
      const branchState = describeBranchState(repoDir, branch);
      console.error(`✗ Push failed: ${pushResult.stderr}`);
      console.error(branchState);
      results.failed.push({
        repo,
        prNumber,
        branch,
        success: false,
        message: `Push failed: ${pushResult.stderr}`,
      });
      continue;
    }
    console.error("✓ Pushed");

    // STEP 3: Run local verification (MANDATORY — no bypass)
    console.error("Running local verification (MANDATORY)...");
    const verification = runVerification(repoDir, getUpstreamBranch(repo), {
      skipInstall: true,
    });

    if (!verification.success) {
      console.error("\n=== STOP: Verification failed ===");
      console.error(
        `PR ${repo}#${prNumber} cannot be merged until verification passes.`
      );
      results.verificationFailed = {
        repo,
        prNumber,
        branch,
        repoDir,
        exitCode: verification.exitCode,
      };
      results.status = "verification_failed";
      results.pending = prs.slice(i + 1);
      exitCode = 1;
      break;
    }

    console.error("✓ Verification passed");

    // STEP 4: Merge via GitHub API
    console.error("Merging via GitHub API...");

    // Brief pause to let GitHub process the push
    await new Promise((resolve) => setTimeout(resolve, 2000));

    const mergeResult = mergePR(repo, prNumber, branch);

    if (mergeResult.success && mergeResult.merged) {
      results.merged.push(mergeResult);
      console.error(`✓ Merged: ${mergeResult.sha?.slice(0, 7)}`);
    } else {
      console.error(`✗ Merge failed: ${mergeResult.message}`);
      results.failed.push(mergeResult);
    }
  }

  // --- Summary ---
  console.error("\n=== Merge Summary ===");
  if (results.merged.length > 0) {
    console.error(`Merged (${results.merged.length}):`);
    for (const r of results.merged) {
      const sha =
        r.sha === "already-merged" ? "already merged" : r.sha?.slice(0, 7);
      console.error(`  ✓ ${r.repo}#${r.prNumber} (${sha})`);
    }
  }
  if (results.skipped.length > 0) {
    console.error(`\nSkipped (${results.skipped.length}):`);
    for (const r of results.skipped) {
      console.error(`  ⚠ ${r.repo}#${r.prNumber}: ${r.reason}`);
    }
  }
  if (results.conflict) {
    console.error(`\nConflict (STOPPED):`);
    console.error(
      `  ✗ ${results.conflict.repo}#${results.conflict.prNumber}: ${results.conflict.reason}`
    );
  }
  if (results.changelogConflict) {
    console.error("\nCHANGELOG conflict (agent can resolve):");
    console.error(
      `  ⚠ ${results.changelogConflict.repo}#${results.changelogConflict.prNumber}`
    );
    console.error(
      `  Files: ${results.changelogConflict.conflictFiles.join(", ")}`
    );
  }
  if (results.verificationFailed) {
    console.error("\nVerification failed (STOPPED):");
    console.error(
      `  ✗ ${results.verificationFailed.repo}#${results.verificationFailed.prNumber}`
    );
  }
  if (results.failed.length > 0) {
    console.error(`\nFailed (${results.failed.length}):`);
    for (const r of results.failed) {
      console.error(`  ✗ ${r.repo}#${r.prNumber}: ${r.message}`);
    }
  }
  if (results.pending.length > 0) {
    console.error(`\nPending (${results.pending.length}):`);
    for (const p of results.pending) {
      console.error(`  ⏸ ${p.repo}#${p.prNumber}`);
    }
  }

  console.log(JSON.stringify(results, null, 2));
  process.exit(exitCode);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
