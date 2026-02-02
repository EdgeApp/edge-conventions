---
name: review-tests
description: Reviews code for test coverage and testability patterns. Use when reviewing files with complex logic that should have unit tests.
---

Review the branch/pull request in context for test coverage and testability.

## Context Expected

You will receive:
- Repository name
- Branch name
- List of changed files to review

## How to Review

1. Read the changed files provided in context
2. Identify complex modules that should have unit tests
3. Check if existing tests adequately cover the changes
4. Report findings with specific file:line references

---

## Ensure Unit Test Coverage

Complex modules should have sufficient unit tests. If a module contains non-trivial logic but lacks tests, this is a code quality issue:

```typescript
// Complex function without tests - needs unit tests
export function calculateFees(
  amount: string,
  feeRates: FeeRate[],
  networkConditions: NetworkConditions
): FeeResult {
  // 50+ lines of complex fee calculation logic
  // Multiple edge cases and conditionals
  // No test coverage
}
```

If a module is difficult to test due to tight coupling or side effects, refactor to make it testable:

```typescript
// Incorrect - untestable due to direct dependencies
export function processTransaction(txData: TxData): void {
  const wallet = getGlobalWallet()  // Hard to mock
  const api = new ApiClient()       // Creates real connection
  // ... complex logic mixed with I/O
}

// Correct - dependency injection enables testing
export function processTransaction(
  txData: TxData,
  wallet: WalletInterface,
  api: ApiInterface
): ProcessResult {
  // Pure logic that can be tested with mock dependencies
}
```

Prioritize test coverage for:
- Business logic and calculations
- Data transformations and parsing
- State management and reducers
- Validation functions
- Utility functions with multiple code paths

A refactor to improve testability is justified when it enables proper test coverage for critical code paths.
