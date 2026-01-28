---
name: review-comments
description: Reviews code for comment quality and documentation patterns. Use when reviewing files for documentation accuracy.
---

Review the branch/pull request in context for comment conventions.

## Context Expected

You will receive:
- Repository name
- Branch name
- List of changed files to review

## How to Review

1. Read the changed files provided in context
2. Check comments for accuracy and necessity
3. Look for missing documentation on non-obvious code
4. Report findings with specific file:line references

---

## Add Non-Obvious Constraints

Document constraints that aren't obvious from the code:

```typescript
// EVM-only: This conversion assumes EVM contract address format
const tokenId = contractAddress.toLowerCase()
```

---

## Remove Stale Comments

Remove comments when the context they describe has changed:

```typescript
// Incorrect - comment no longer needed after refactor
// This is a workaround for bug XYZ
const result = normalFunction()

// Correct - just remove the comment
const result = normalFunction()
```

---

## Comments Should Explain Why, Not What

Good comments explain the reasoning, not the mechanics:

```typescript
// Incorrect - describes what code does (obvious)
// Loop through items and filter by status
const filtered = items.filter(item => item.status === 'active')

// Correct - explains why
// Only active items can be edited; archived items are read-only
const filtered = items.filter(item => item.status === 'active')
```
