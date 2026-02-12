# Cursor Rules Research: Maximizing Instruction-Following Compliance

## Goal

Achieve 100% coverage of defined coding rules when the agent edits TS/TSX files, while minimizing unnecessary context for unrelated prompts.

---

## Key Findings

### 1. Rule Activation Is Two-Stage (Not Guaranteed)

According to a [reverse-engineering of Cursor's rule system](https://meetcursor.com/posts/a-deep-dive-into-cursor-rules-045/), rules go through two stages:

1. **Injection** — The rule text enters the system prompt context (controlled by `alwaysApply`, `globs`, or manual `@`-mention).
2. **Activation** — The AI decides whether to use the rule. Cursor wraps injected rules with: *"Use them if they seem useful to the user's most recent query, but do not use them if they seem unrelated."*

This means even `alwaysApply: true` rules are **not guaranteed to be followed** — the AI makes a relevance judgment at activation time based on the `description` field.

**User Rules bypass this gate.** They are always sent directly into the system prompt without the "use if relevant" wrapper, making them the highest-reliability option for critical rules.

### 2. Glob Patterns Are Unreliable

Multiple Cursor forum reports document glob pattern failures:

- **Multi-folder workspaces**: Glob patterns silently fail to match files when using multi-root workspaces (`.code-workspace` files or "Add Folder to Workspace"). Rules in root `.cursor/rules/` are not discovered. ([forum report, Aug 2025](https://forum.cursor.com/t/cursor-rules-not-working-properly-in-multi-root-workspace-monorepo/132244))
- **Spacing breaks globs**: `**/*.ts, **/*.tsx` (with space after comma) silently fails. Must be `**/*.ts,**/*.tsx`. ([forum report, Jul 2025](https://forum.cursor.com/t/cursor-rules-globs-inconsistencies/116958))
- **Thinking model timing**: For thinking/reasoning models, auto-attached and agent-requested rules are pulled in **after** thinking has occurred, meaning they may not influence the model's reasoning phase. ([forum report](https://forum.cursor.com/t/for-thinking-models-agent-requested-and-auto-attached-rules-are-pulled-in-after-thinking-has-occurred/84787))
- **No parent traversal**: Cursor doesn't walk up directories to find `.cursor/rules/` in parent folders.

These issues are architectural limitations that have persisted across multiple Cursor versions (Dec 2024 through Jan 2026).

### 3. Single Large File vs. Multiple Files

**Conclusion: Keep as a single file when all rules share the same scope.**

Sources:
- [Anthropic's prompting best practices](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices): XML tags create structural boundaries that prevent the model from confusing instructions with examples. Nested tags work well for hierarchical content.
- [Anthropic's XML tags guide](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/use-xml-tags): Consistent tag names and nested structure improve accuracy.
- [CDCT benchmark (arXiv:2512.17920)](https://arxiv.org/abs/2512.17920): LLMs show a U-curve in constraint compliance — very short and fully detailed instructions both outperform medium-length ones.

Splitting only helps when:
- Rules apply to different file types (use different globs to reduce context)
- The file exceeds ~500 lines
- Rules are thematically unrelated (e.g., git conventions mixed with TS patterns)

If all rules share the same glob/scope and are thematically cohesive, splitting just fragments the XML hierarchy without reducing what the model sees.

### 4. Passive Pointer vs. Inline Content vs. Skills (Vercel AGENTS.md Findings)

[Vercel's evaluation](https://vercel.com/blog/agents-md-outperforms-skills-in-our-agent-evals) tested three approaches for giving agents access to documentation:

| Approach | Implementation | Pass rate |
|---|---|---|
| No docs | Baseline | 53% |
| Skills (no explicit instructions) | Agent must decide to invoke a skill | 56% (+3pp) |
| Skills (with explicit instructions) | Agent is told to use the skill | 79% (+26pp) |
| **AGENTS.md docs index** | **Compressed file-path index always in context** | **100% (+47pp)** |

**The 100% tier does NOT inline full content.** They compressed a 40KB docs payload down to an 8KB file-path index embedded in `AGENTS.md`. The agent then reads the actual doc files on demand using tool calls. The key distinction:

- **Skills** require the agent to decide *whether* to look something up → 56% non-invocation rate
- **AGENTS.md pointer** removes that decision — the agent always knows *where* things are, and just reads the file when relevant

This is a **passive pointer + active read** pattern, not a "dump everything into the prompt" pattern.

#### Mapping to Cursor

| Vercel concept | Cursor equivalent |
|---|---|
| AGENTS.md with file-path index | User Rule or `alwaysApply: true` rule containing a short pointer to the standards file |
| Agent reads doc files on demand | Agent uses Read tool on the referenced standards file before editing |
| Skills (agent decides to invoke) | Agent-requestable rules / `description`-based rules |

The `load-standards-by-filetype.mdc` meta-rule with `alwaysApply: true` is effectively this pattern — the pointer is always in context, and the agent reads the actual file when it encounters TS/TSX work. Placing the pointer in User Rules instead adds further reliability by bypassing the "use if relevant" activation gate.

#### First-Person Framing

An [HN commenter](https://news.ycombinator.com/item?id=46809708) tested first-person vs. second-person framing and found:
- "I will follow the instructions in AGENTS.md" → 3/3 compliance
- "Follow the instructions in AGENTS.md" → 0/3 compliance

Small sample, but directionally useful. Using first-person framing ("I will read and follow...") in the pointer may improve compliance.

### 5. User Rules vs. Project Rules

| Aspect | User Rules | Project Rules (`alwaysApply: true`) | Project Rules (glob) |
|---|---|---|---|
| Injection reliability | Always injected | Always injected | Unreliable in multi-folder workspaces |
| Activation gate | No "use if relevant" wrapper | Wrapped with relevance judgment | Wrapped with relevance judgment |
| Thinking model timing | In base system prompt | In base system prompt | Loaded AFTER thinking phase |
| Version controlled | No | Yes | Yes |
| Team shareable | No | Yes | Yes |
| Project scoped | No (applies to all projects) | Yes | Yes |
| Multi-workspace support | Works everywhere | May not be found in multi-root | Breaks in multi-root |

**User Rules are the highest-reliability option** — they bypass glob bugs, the "use if relevant" wrapper, and the thinking-model timing issue. They can be short pointers (not full content) following the Vercel pattern.

### 6. Model Compliance Has Inherent Limits

No published empirical data exists measuring Cursor rule compliance rates specifically.

Relevant LLM research:
- [IFBench (NeurIPS 2025)](https://arxiv.org/abs/2507.02833): Leading models score below 50% on **novel, unfamiliar** verifiable output constraints (word counting, ratio maintenance, formatting manipulation), while scoring 80%+ on the 25 familiar IFEval constraint types. This demonstrates an overfitting gap, not a universal compliance ceiling.
- **Standard coding conventions** (no `any`, `??` over `||`, functional components) are well-represented in training data and likely see high compliance.
- **Project-specific conventions** (`asJSON` cleaner, `lstrings.*`, `useHandler` over `useCallback`, `_1s`/`_2s` suffix patterns) have no pre-training basis and rely entirely on the rule text — these will have inherently lower compliance.
- [CDCT (arXiv:2512.17920)](https://arxiv.org/abs/2512.17920): RLHF "helpfulness" training is the dominant cause of constraint violations. The model's instinct to be "helpful" can override explicit constraints.

### 7. Auto Format on Agent Finish

Cursor's "Auto Format on Agent Finish" setting runs the project's configured formatter (e.g., Prettier) on agent-modified files after the agent completes its turn. This means:
- The agent doesn't need to spend tokens running `yarn fix` or manually fixing formatting
- A workspace rule (`no-format-lint.mdc`) was created to prevent the agent from wasting tokens on formatting fixes

Note: Auto Format only handles pure formatting. It does not run lint fixes beyond formatting (e.g., `simple-import-sort` reordering).

---

## Recommendations

1. **Use a User Rule as a passive pointer** — a short instruction like `"When editing .ts/.tsx files, I will read ~/.cursor/rules/typescript-standards.mdc and follow its rules"` in User Rules. This follows the Vercel AGENTS.md pattern (always-present pointer, on-demand content read) while bypassing the activation gate.
2. **Keep the full standards in a separate file** (`typescript-standards.mdc`) — don't inline the full content into User Rules. The file stays version-controlled and editable; the pointer stays lightweight.
3. **Keep `alwaysApply: true` on the standards file as a fallback** — if Cursor loads it as a global rule directly, the agent gets the content without even needing the Read tool call, which is strictly better.
4. **Use XML tags** for internal structure (already in place in `typescript-standards.mdc`).
5. **Provide concrete examples** for project-specific conventions — these have the lowest baseline compliance and benefit most from few-shot demonstration.
6. **Use first-person framing** in pointer rules ("I will read and follow...") — early evidence suggests this improves compliance vs. imperative framing.
7. **Avoid aggressive language** like "CRITICAL: You MUST" — Claude 4.6 is more responsive to system prompts and will overtrigger. Use normal phrasing.
8. **Don't rely on globs** if you use multi-repo workspaces.
9. **Keep rules in a single file** when they share the same scope — don't split unless different file types or themes warrant it.

---

## Sources

- [Cursor Rules Official Docs](https://cursor.com/docs/context/rules)
- [Vercel: AGENTS.md Outperforms Skills in Agent Evals](https://vercel.com/blog/agents-md-outperforms-skills-in-our-agent-evals)
- [HN Discussion: AGENTS.md vs Skills](https://news.ycombinator.com/item?id=46809708)
- [Anthropic Prompting Best Practices](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices)
- [Anthropic XML Tags Guide](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/use-xml-tags)
- [Anthropic Long Context Tips](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/long-context-tips)
- [Cursor Rules Activation Deep Dive](https://meetcursor.com/posts/a-deep-dive-into-cursor-rules-045/)
- [IFBench: Generalizing Verifiable Instruction Following (NeurIPS 2025)](https://arxiv.org/abs/2507.02833)
- [CDCT: Constraint Compliance Under Compression (arXiv:2512.17920)](https://arxiv.org/abs/2512.17920)
- [Cursor Forum: Glob Inconsistencies](https://forum.cursor.com/t/cursor-rules-globs-inconsistencies/116958)
- [Cursor Forum: Multi-Root Workspace Rules](https://forum.cursor.com/t/cursor-rules-not-working-properly-in-multi-root-workspace-monorepo/132244)
- [Cursor Forum: Thinking Model Timing](https://forum.cursor.com/t/for-thinking-models-agent-requested-and-auto-attached-rules-are-pulled-in-after-thinking-has-occurred/84787)
