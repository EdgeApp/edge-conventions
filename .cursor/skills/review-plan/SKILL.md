---
name: review-plan
description: Review a development plan for specificity, architecture, tests, and E2E coverage. Use when reviewing or drafting plans so they are executable without discovery.
---

# Review Plan Skill

Review a development plan document to ensure it is **execution-ready**: specific about repositories and code, clear on architecture, and complete with unit tests and step-by-step end-to-end testing. The plan must **not** leave decision trees or open discovery for the executing agent—all such choices must be resolved and written down before execution.

---

## When to Use

- Before handing a plan to an agent or team for implementation
- When drafting a new development plan in `edge-plans` or similar
- When a plan has failed execution due to ambiguity or missing steps
- When the user asks to "review this plan" or "make this plan executable"

---

## Step 1: Obtain the Plan

- **Input**: Path to the plan document (e.g. `edge-plans/2026-02/<name>.md`) or the plan content itself.
- Read the full document. If the user provided a path, read from the workspace; otherwise use the pasted content.

---

## Step 2: Check Repository and Code Specificity

The plan must name **repositories** and **exact files** (or clear file patterns) that will be created or modified. Vague references like "the exchange plugin" or "the GUI" are insufficient.

### Checklist

- [ ] **Repositories listed explicitly** — Every repo that will be touched is named (e.g. `edge-exchange-plugins`, `edge-currency-accountbased`, `edge-react-gui`).
- [ ] **File-level specificity** — For each change, the plan specifies either:
  - Exact file path (e.g. `src/swap/defi/gravityBridge.ts`), or
  - A clear pattern plus a concrete example (e.g. "new Cosmos chain info file following `coreumInfo.ts`" with the new filename given).
- [ ] **New files vs modified files** — New files are marked as **new** and existing files as **modified**; registration points (e.g. `src/index.ts`, `cosmosInfos.ts`) are explicitly mentioned.
- [ ] **No "figure out where"** — There are no instructions that require the executor to search the codebase to decide where to add code; the plan states the target file and, if relevant, the function or export to add.

**Example (good)**: "Create `src/cosmos/info/gravitybridgeInfo.ts` following the pattern from `coreumInfo.ts`. Register in `src/cosmos/cosmosInfos.ts` by adding the import and adding `gravitybridge` to `cosmosPlugins`."

**Example (bad)**: "Add Gravity Bridge support to the Cosmos plugins."

---

## Step 3: Check Architecture and Design

The plan must document **architecture and design decisions** so the executor does not have to infer or choose.

### Checklist

- [ ] **Background / context** — Enough context (token IDs, chain IDs, contract addresses, APIs) is written so the executor does not need to look them up.
- [ ] **Decisions resolved** — Any "we could do A or B" or "TBD" is resolved and one option is specified with a short rationale (e.g. "PFM not supported → use two-hop flow").
- [ ] **No open discovery** — There are no steps like "determine the correct API endpoint" or "check whether the engine supports X"; the plan either states the outcome of that check or includes a **concrete verification step** with a pass/fail and a fallback (e.g. "If amino is not supported → use protoMsgs; the executing agent must test both paths").
- [ ] **Interfaces and data flow** — For plugins or multi-repo work, the plan describes how components interact (e.g. "Plugin returns SwapOrder with preTxs for approval; engine handles MakeTxDexSwap with this message type").
- [ ] **Closest analogues** — For new plugins or features, the plan names existing code that is the template (e.g. "Follow `fantomSonicUpgrade` for EVM bridge pattern, `cosmosIbc` for IBC leg").

---

## Step 4: Check Unit Tests

The plan must require **concrete unit tests** where logic is added.

### Checklist

- [ ] **Test file(s) specified** — Path to test file(s) is given (e.g. `test/gravityBridge.test.ts`).
- [ ] **Test cases described** — The plan lists specific test cases or categories, e.g.:
  - Validation (reject invalid pairs, accept valid pairs)
  - Fee/rate calculations
  - Encoding (ABI, message format)
  - Error paths
- [ ] **Framework and style** — If the repo has a standard (e.g. Mocha/Chai, Jest), the plan says tests follow existing patterns in that repo.
- [ ] **Gate** — The plan includes a precommit/gate step (e.g. `yarn precommit` or `yarn test`) that must pass before proceeding.

---

## Step 5: Check End-to-End and Integration Testing

The plan must include **step-by-step E2E testing** so an agent or human can run it without guessing.

### Checklist

- [ ] **Environment** — How to set up the test environment is specified (e.g. link local deps via `package-deps`, enable debug servers, `env.json` flags, Metro + simulator).
- [ ] **Build and launch** — Explicit steps or a reference to a skill (e.g. `debug-edge` skill) for building and launching the app on simulator.
- [ ] **Test account and credentials** — Where credentials come from (e.g. `testerConfig.json`) and what wallets/balances the test account must have; if the plan assumes pre-created wallets, that is stated.
- [ ] **Step-by-step UI flow** — E2E tests are written as numbered steps that an executor (or Maestro) can follow, e.g.:
  - Navigate to Exchange → select From wallet → select From token → select To wallet → select To token → enter amount → tap Next → wait N seconds → assert quote appears.
- [ ] **Simulator + Maestro** — If the change affects the app UI or swap/plugin flow, the plan specifies testing on the iOS simulator and, where appropriate, using the Maestro MCP server (e.g. `inspect_view_hierarchy`, `tap_on`, `input_text`, `take_screenshot`) with explicit gates (e.g. "Gravity Bridge appears as quote provider within 15 seconds").
- [ ] **Gates** — Each E2E scenario has a clear pass/fail gate and, when relevant, timeout and retry rules (e.g. "Success screen within 120 seconds; max 2 retries").
- [ ] **Artifacts** — Screenshot labels or artifact names are specified so results can be reported (e.g. `quote-eth-to-gravitybridge`, `e2e-eth-to-grav-success`).

---

## Step 6: Check No Decision Trees Left to Discovery

The plan must **not** require the executor to "figure out" or "discover" anything that could have been decided upfront.

### Checklist

- [ ] **No "investigate" without a follow-up** — If the plan says to investigate something (e.g. "Check if engine supports MsgSendToEth"), it must also state: (a) how to check, and (b) what to do in each outcome (e.g. "If amino not supported, use protoMsgs; agent must test both paths").
- [ ] **No unbounded choices** — There are no open-ended choices (e.g. "pick an appropriate timeout") without a specified value or rule (e.g. "maxFulfillmentSeconds: 1200").
- [ ] **Constants and config** — Addresses, chain IDs, denoms, and magic numbers are written in the plan, not "to be configured later."
- [ ] **Implementation order** — The plan includes an ordered list or table of implementation steps (and optionally which gate must pass before the next), so the executor does not have to infer order.

---

## Step 7: Required Structural Elements (From Reference Plan)

- [ ] **Final deliverables table** — List of concrete artifacts (files, branches, PRs) that define "done."
- [ ] **Success metrics / automated gates** — All gates listed in one place with pass/fail criteria and commands.
- [ ] **Failure escalation** — What to do when a gate fails after max retries (e.g. write log to `/tmp`, stop, report).
- [ ] **Files changed summary** — At the end, a concise list of repo + path + new/modified for quick reference.

**Optional**: **Estimated effort** — Rough time per phase so scope is clear.

---

## Step 8: Produce the Review

1. **Summary** — One paragraph: does the plan meet the bar for execution-ready (yes / no / partial), and the main gaps if any.
2. **Findings** — For each checklist section (2–7), list:
   - **Pass**: What the plan does well (brief).
   - **Gaps**: Missing or vague items with a concrete suggestion (e.g. "Add exact file path for the new plugin; see gravity-bridge-nym-integration.md Phase 2.2.")
3. **References** — Point to sections in `edge-plans/2026-02/gravity-bridge-nym-integration.md` that illustrate the desired level of detail (e.g. "Phase 5.2.5 for step-by-step Maestro E2E", "Phase 2.4 for unit test cases", "Implementation Order table for step sequence").

If the user asked to **improve** the plan, produce an edited or annotated version of the plan that fills the gaps (or a patch/supplement document) rather than only listing issues.

---

## Output Format

Deliver the review as markdown with clear headings:

- **Summary**
- **Repository and code specificity**
- **Architecture and design**
- **Unit tests**
- **E2E and integration testing**
- **Decision trees / discovery**
- **Required structural elements** (deliverables table, gates, failure escalation, files-changed summary)
- **Recommendations** (prioritized list of changes to make)
- **Reference sections** (links or paths to the Gravity Bridge plan)

Keep the review actionable: every gap should map to a concrete edit or addition the author can make.
