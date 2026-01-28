---
name: review-errors
description: Reviews code for error handling patterns, async operations, and TypeScript type safety. Use when reviewing files with try/catch, promises, or error handling.
---

Review the branch/pull request in context for error handling conventions.

## Context Expected

You will receive:
- Repository name
- Branch name
- List of changed files to review

## How to Review

1. Read the changed files provided in context
2. Look for try/catch blocks, promise chains, async functions
3. Verify error handling follows conventions
4. Report findings with specific file:line references

---

## Preserve Stack Traces

Don't use shorthand `.catch(showError)` - it loses the calling file from stack traces:

```typescript
// Incorrect - ScanModal.tsx won't appear in stack trace
doSomething().catch(showError)

// Correct - preserves stack trace
doSomething().catch((error: unknown) => showError(error))
```

---

## Error Variable Naming

Prefer `error` over `err` or `e` for caught exceptions:

```typescript
// Correct
try {
  // ...
} catch (error) {
  // ...
}

// Incorrect
try {
  // ...
} catch (err) {
  // ...
}
```

---

## Avoid @ts-expect-error

Don't double down on `@ts-expect-error` comments when trivial fixes exist:

```typescript
// Incorrect
// @ts-expect-error
const result = someFunction()

// Correct - fix the type issue
const result: ExpectedType = someFunction() ?? defaultValue
```

Use `?? []`, `?? {}`, or explicit type annotations instead of suppressing errors.

---

## Understand undefined vs null Semantics

When checking for changes, understand that `undefined` and `null` have different meanings:

```typescript
// Incorrect - treats null and undefined the same
const anyChanged = nameChange != null || categoryChange != null

// Correct - null means "delete the field", which IS a change
const anyChanged = nameChange !== undefined || categoryChange !== undefined
```

Use `!== undefined` when `null` has semantic meaning (like "delete this field").

---

## Remove Unguarded Debug Logging

Don't commit unguarded `console.log` statements to production code:

```typescript
// Incorrect - unguarded debug log left in code
console.log('metadata:', metadata)
await wallet.saveTxMetadata(params)

// Correct - remove debug logging entirely, or guard it
// (see "Guard Debug Logging" in review-code-quality.md)
await wallet.saveTxMetadata(params)
```

---

## Always Await Async Operations

Always `await` async operations to get proper spinners and double-click prevention:

```typescript
// Incorrect - no await, race conditions possible
const handleSave = () => {
  wallet.saveTxMetadata(params).catch(showError)
}

// Correct - await provides proper UI feedback
const handleSave = async () => {
  await wallet.saveTxMetadata(params)
}
```

The `await` stops one save from running at the same time as another, preventing race conditions.

---

## Remove Unnecessary Catch Blocks

When the whole function is async and the caller handles errors, you don't need a separate `.catch()`:

```typescript
// Incorrect - redundant catch when function is async
const handleSave = async () => {
  await wallet.saveTxMetadata(params).catch((error: unknown) => {
    showError(error)
  })
}

// Correct - async function, caller handles errors
const handleSave = async () => {
  await wallet.saveTxMetadata(params)
}
```

---

## TokenId Dereference Must Not Fall Back to Null

When `tokenId` is a non-null string and is used to dereference token information, the lookup must not fall back to `null` or `undefined`. Doing so changes the semantic meaning from "this specific token" to "native currency", which can cause incorrect behavior like swapping the wrong asset.

```typescript
// Incorrect - falling back to null changes the intended token
function getContractAddress(
  wallet: EdgeCurrencyWallet,
  tokenId: string | null
): string | null {
  if (tokenId == null) return null  // OK - explicitly no token
  const token = wallet.currencyConfig.allTokens[tokenId]
  if (token == null) return null  // BUG: tokenId exists but lookup failed
  return token.networkLocation?.contractAddress ?? null  // BUG: token found but no address
}
```

If `tokenId` is a string, the caller intends to operate on that specific token. A failed lookup should throw, not silently fall back:

```typescript
// Correct - throw when tokenId lookup fails
function getContractAddress(
  wallet: EdgeCurrencyWallet,
  tokenId: string | null
): string | null {
  if (tokenId == null) return null
  const token = wallet.currencyConfig.allTokens[tokenId]
  if (token == null) {
    throw new Error(`Token not found for tokenId: ${tokenId}`)
  }
  const contractAddress = token.networkLocation?.contractAddress
  if (contractAddress == null) {
    throw new Error(`Contract address not found for token: ${tokenId}`)
  }
  return contractAddress
}
```

**Rule:** When `tokenId` is a string, any dereference using it must succeed or throw. Never fall back to `null`/`undefined` as this changes the intended asset.

---

## Consolidate Redundant Guard Clauses

When a parameter is validated in multiple branches, check it once at the top:

```typescript
// Incorrect - redundant null checks in both branches
function formatCurrency(
  networkCode: string | null,
  contractAddress: string | null
): string | object {
  if (contractAddress == null) {
    if (networkCode == null) {
      throw new Error('Network code required')
    }
    return networkCode
  }

  if (networkCode == null) {
    throw new Error('Network code required')
  }
  return { contract_address: contractAddress, network: networkCode }
}
```

Since `networkCode` is required in ALL code paths, validate once at the top:

```typescript
// Correct - single guard clause at the top
function formatCurrency(
  networkCode: string | null,
  contractAddress: string | null
): string | object {
  if (networkCode == null) {
    throw new Error('Network code is required')
  }

  if (contractAddress == null) {
    return networkCode
  }

  return { contract_address: contractAddress, network: networkCode }
}
```

**Rule:** If a validation applies to all code paths, perform it once at function entry.

---

## Don't Add Redundant Error Handling

When a global error handler already catches and displays errors, don't add local `.catch(showError)` calls:

```typescript
// Incorrect - redundant when global handler exists
const handlePress = async () => {
  try {
    await doSomething()
  } catch (error) {
    showError(error)  // Global handler already does this
  }
}

// Correct - let global handler catch it
const handlePress = async () => {
  await doSomething()
}
```

The codebase uses `withExtendedTouchable` and similar HOCs that catch promise rejections and call `showError`. Adding local error handling duplicates this work and can cause errors to be shown twice.

Only add explicit error handling when:
- You need to handle specific error types differently
- You need to perform cleanup before re-throwing
- There's no global handler in the call chain

---

## Handle User Cancellation Gracefully

When a user cancels an operation, don't show a generic error message:

```typescript
// Incorrect - shows error for intentional cancellation
try {
  await userInputModal()
} catch (error) {
  showError(error)  // Shows "User cancelled" as an error
}

// Correct - check if it's a cancellation
try {
  await userInputModal()
} catch (error) {
  if (error instanceof UserCancelledError) return
  showError(error)
}
```

User-initiated cancellations (closing modals, pressing back) should exit silently.

---

## Don't Mask Errors with Generic Messages

Catch blocks should not always throw the same error regardless of what actually went wrong:

```typescript
// Incorrect - masks network errors, server errors, etc.
const verifyOtp = async (code: string) => {
  try {
    await api.verify(code)
  } catch (error) {
    throw new Error('Invalid verification code')  // Hides real error
  }
}

// Correct - only throw specific message for expected errors
const verifyOtp = async (code: string) => {
  try {
    await api.verify(code)
  } catch (error) {
    if (error instanceof ApiError && error.status === 400) {
      throw new Error('Invalid verification code')
    }
    throw error  // Preserve original error for network/server issues
  }
}
```

Users should see accurate error messages so they can take appropriate action.

---

## Localization in Error Messages

See "Localization Belongs at GUI Level" in review-strings.md. Error messages thrown from API/plugin layers should be structured errors, not localized strings.

---

## Check Array Bounds Before Indexing

When accessing array elements by index, verify the array has elements to avoid undefined access:

```typescript
// Incorrect - undefined access when array is empty
const address = vin.addresses[0]  // undefined if addresses is []
const scriptPubkey = validScriptPubkeyFromAddress(address)
// Error message shows "undefined" as the address

// Correct - check before accessing
const address = vin.addresses[0]
if (address == null) {
  // Handle the empty case appropriately
  continue  // or throw with meaningful message
}
const scriptPubkey = validScriptPubkeyFromAddress(address)
```

This is especially important when the array can legitimately be empty according to type definitions (e.g., `addresses: string[]` with default `[]`).

---

## Compare Same Types: TokenIds vs Currency Codes

Don't compare tokenIds with currency codes - they are different identifiers:

```typescript
// Incorrect - comparing wrong identifier types
function checkInvalidTokenIds(
  fromCurrencyCode: string,  // This is a currency code like "BTC"
  invalidTokenIds: string[]  // These are tokenIds like contract addresses
) {
  // BUG: Currency codes will never match tokenIds
  return invalidTokenIds.includes(fromCurrencyCode)
}

// Correct - compare tokenIds with tokenIds
function checkInvalidTokenIds(
  fromTokenId: string | null,  // Token identifier (null for mainnet)
  invalidTokenIds: Array<string | null>
) {
  return invalidTokenIds.includes(fromTokenId)
}
```

**Rule:** When checking against a list of tokenIds, pass the actual tokenId (from `request.fromTokenId`), not the currency code.

---

## Lookup Tables Must Have Defensive Access

When accessing lookup tables by dynamic key, handle missing entries gracefully:

```typescript
// Incorrect - undefined.includes() throws TypeError
const NON_STANDARD_TOKENS: Record<string, string[]> = {
  ethereum: ['0x123...', '0x456...']
}

function isNonStandard(pluginId: string, tokenId: string): boolean {
  // BUG: Returns undefined for 'arbitrum', then .includes() throws
  return NON_STANDARD_TOKENS[pluginId].includes(tokenId)
}

// Correct - use optional chaining or default
function isNonStandard(pluginId: string, tokenId: string): boolean {
  return NON_STANDARD_TOKENS[pluginId]?.includes(tokenId) ?? false
}
```
