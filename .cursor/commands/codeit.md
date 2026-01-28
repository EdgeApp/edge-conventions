# codeit

Execute a planning document and iteratively refine the implementation until it passes code review.

## Input

- **Planning document**: Freeform markdown provided in the prompt (typically AI-generated)
- **Repository**: Specified in the planning document
- **Branch**: Assume the user is already on the correct branch

## Execution Flow

### Phase 1: Preparation

1. Stash any uncommitted changes (preserve the working directory)
2. Identify the target repository from the planning document
3. Change to the repository directory

### Phase 2: Implementation

1. Parse and execute the implementation steps from the planning document
2. Do not commit changes unless the planning document explicitly specifies commits

### Phase 3: Build Verification

1. Detect available build/lint commands:
   - Check `package.json` for `precommit`, `lint`, `build`, `types` scripts
   - Prefer `yarn precommit` if available
2. Run the build verification
3. Fix any errors and re-run until build passes

### Phase 4: iOS Testing (Conditional)

If the target repository is `edge-react-gui` or one of its dependencies, test the changes in the iOS simulator:

**Affected repositories**:
- `edge-react-gui` (main app)
- `edge-core-js` (core account/wallet management)
- `edge-currency-accountbased` (ETH, etc.)
- `edge-currency-plugins` (BTC, etc.)
- `edge-exchange-plugins` (swap providers)

**Testing workflow**:
1. Follow the `@.cursor/skills/debug-edge/SKILL.md` skill to build and launch the app
2. For dependency repos, enable the appropriate debug flag in `edge-react-gui/env.json` and run `yarn start` in the dependency repo
3. Verify the changes work as expected in the simulator
4. If issues are found, fix them and re-run build verification before proceeding

### Phase 5: Review Loop

Iterate until the code passes review (maximum 5 iterations):

1. **Run local code review** by executing the `/edge-conventions/revpr` command:
   - Pass "current branch" as the target
   - revpr will run all applicable review subagents and generate a findings report
   - Do NOT pause for user review - continue automatically
2. Read the generated review file from `/tmp`
3. If no Critical Issues or Warnings found, exit the loop
4. **Fix the issues** identified in the review:
   - Address each Critical Issue and Warning
   - Suggestions are optional - fix if straightforward
5. Re-run build verification
6. **Re-test in iOS simulator** (if edge-react-gui or dependencies are affected):
   - Verify fixes don't break existing functionality
   - Use the debug-edge skill workflow from Phase 4
7. Return to step 1

### Phase 6: Completion

1. Report success to the user
2. Summarize the implementation and any fixes made
3. Restore any stashed changes

## Constraints

- **No push**: Never push to GitHub automatically
- **No PR creation**: This command works entirely locally
- **Local review only**: Do not require or interact with GitHub PRs
- **Max 5 iterations**: Stop after 5 review cycles even if issues remain
