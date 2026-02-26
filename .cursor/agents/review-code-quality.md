---
name: review-code-quality
description: Reviews code for general quality patterns including naming, dead code, and code organization. Use for general code quality review.
---

Review the branch/pull request in context for code quality conventions.

## Context Expected

You will receive:
- Repository name
- Branch name
- List of changed files to review

## How to Review

1. Read the changed files provided in context
2. Check for naming, dead code, organization issues
3. Verify code quality follows conventions
4. Report findings with specific file:line references

---

## Delete Unnecessary Code

Don't leave dead or unused code in the codebase:

```typescript
// Incorrect - leaving unused code "just in case"
const unusedVariable = calculateSomething()
// Maybe useful later?

// Correct - delete it
// (If needed later, git history has it)
```

---

## Use Meaningful Variable Names

Avoid abbreviations that aren't immediately clear:

```typescript
// Incorrect - unclear abbreviation
const kavProps = { ... }

// Correct - descriptive name
const avoidKeyboard = { ... }
// or
const keyboardAvoidingProps = { ... }
```

---

## Put Parameters Inline

Don't declare variables just to pass them to a function:

```typescript
// Incorrect - old pattern
const params = {
  txid: transaction.txid,
  tokenId: tokenId,
  metadata: metadataToSave
}
await wallet.saveTxMetadata(params)

// Correct - inline parameters
await wallet.saveTxMetadata({
  txid: transaction.txid,
  tokenId: tokenId,
  metadata: metadataToSave
})
```

Only exception is when calling a function that has unknown type parameters. Use a typed constant to ensure the call provides the correct parameters:

```typescript
interface CreateUserBody {
  username: string
  email: string
  role: 'admin' | 'user'
}

// Correct - typed constant ensures body matches expected schema
const body: CreateUserBody = {
  username: 'john',
  email: 'john@example.com',
  role: 'admin'
}
await fetch('/api/users', {
  method: 'POST',
  body: wasCreateUserBody(body)
})
```

When using the cleaners library, prefer uncleaners (`wasX`) over `JSON.stringify` for serialization. This catches type errors at compile time when the API contract changes.

---

## Use Existing Helpers

Use existing helper functions instead of creating new ones:

```typescript
// Incorrect - creating redundant helper
const getCurrencyCodeMultiplier = (config, code) => { ... }

// Correct - use existing helper
const { multiplier } = getExchangeDenom(currencyConfig, tokenId)
```

Before creating a new utility, check if an existing one serves the purpose:
- `getTokenId` / `getTokenIdForced` instead of `getWalletTokenId`
- `getExchangeDenom` instead of custom multiplier lookups

---

## Avoid Duplicated Mock Data

Use existing mock data from `src/util/fake/` or consolidate new mocks there:

> "We have been plagued by lots of duplicated, half-baked mock data. This makes it hard to perform core changes without breaking things. Our goal is to reduce the duplication over time, not add to it."

---

## Optimize Search Functions

Move expensive operations outside loops:

```typescript
// Incorrect - calls normalizeForSearch for each term
searchTerms.every(term => {
  const normalCurrencyCode = normalizeForSearch(currencyCode)
  return normalCurrencyCode.startsWith(term)
})

// Correct - normalize once outside the loop
const normalCurrencyCode = normalizeForSearch(currencyCode)
const normalDisplayName = normalizeForSearch(displayName)

return searchTerms.every(term =>
  normalCurrencyCode.startsWith(term) ||
  normalDisplayName.startsWith(term)
)
```

Combine conditions into single `||` chains instead of nested `if`/`return` blocks.

---

## Remove Unused Style Definitions

Delete style properties that aren't used by any component:

```typescript
// Incorrect - unused styles left in StyleSheet
const styles = StyleSheet.create({
  container: { flex: 1 },
  unusedHeader: { fontSize: 24 },  // Not referenced anywhere
  unusedFooter: { padding: 10 }    // Not referenced anywhere
})

// Correct - only define styles that are used
const styles = StyleSheet.create({
  container: { flex: 1 }
})
```

Unused styles add noise and can mislead future developers.

---

## No Hardcoded Debug URLs or Flags

Never commit hardcoded sandbox URLs or debug flags:

```typescript
// Incorrect - hardcoded sandbox URL
const API_URL = 'https://sandbox.api.example.com/v1'

// Incorrect - debug flag left enabled
const DEBUG_MODE = true

// Correct - use environment configuration
const API_URL = envConfig.apiUrl
const DEBUG_MODE = __DEV__
```

Debug configurations should come from environment variables or build-time constants, never hardcoded values.

---

## Local Path Dependencies Require Linked PRs

Local file path dependencies in `package.json` (e.g., `"edge-core-js": "../edge-core-js"`) are acceptable when the PR has a linked dependency PR that must be published first. This is the standard workflow for cross-repo changes.

When reviewing, if you see a local path dependency:
- Verify the PR description references a dependent PR from the dependency library
- That dependency PR must be published before this PR can be merged
- The local path should be replaced with the published version at merge time

---

## Guard Debug Logging

Production code should not have unguarded `console.log` statements. Use debug flags:

```typescript
// Incorrect - logs in production
console.log('response:', response)

// Correct - guarded by debug flag
if (ENV.DEBUG_VERBOSE_LOGGING) {
  console.log('response:', response)
}
```

Unguarded logging can expose sensitive data and clutter production logs.

---

## Validation Logic Should Not Be Duplicated

When validating form fields, use a single validation function for both real-time and submit-time checks:

```typescript
// Incorrect - different validation thresholds
const isFormValid = accountNumber.length >= 4  // Allows submission
const validateField = () => {
  if (accountNumber.length < 8) return 'Too short'  // Shows error
}
// User can submit with 5 digits, then see error

// Correct - single source of truth
const validateAccountNumber = (value: string) => {
  if (value.length < 8) return 'Account number must be at least 8 digits'
  return null
}

const isFormValid = validateAccountNumber(accountNumber) === null
```

Duplicated validation logic leads to inconsistent UX where users can submit invalid forms.

---

## Avoid Deprecated Methods

Don't use deprecated API methods when local alternatives exist. Check for deprecation markers (`@deprecated` in JSDoc or type definitions) and use the recommended replacement.

---

## Use rfc4648 for All Base64 and Hex Conversions

Use the `rfc4648` library for all base64 and hex encoding/decoding. Do not use hand-rolled implementations or `Buffer.toString('hex')`:

```typescript
// Incorrect - hand-rolled base64 encoding
const toBase64 = (data: Uint8Array): string => {
  // ... manual implementation
}

// Incorrect - using Buffer for hex
const hex = Buffer.from(data).toString('hex')

// Correct - use rfc4648 library
import { base16, base64 } from 'rfc4648'
const encoded = base64.stringify(data)
const decoded = base64.parse(encodedString)
const hex = base16.stringify(data).toLowerCase()
```

`Buffer` is not available in all environments (React Native WebView), and hand-rolled implementations risk subtle bugs.

---

## Keep Configuration Consistent

When a value appears in multiple configuration locations, ensure they match:

```typescript
// Bug: Deprecated default doesn't match engineInfo config
const deprecatedDefaultSettings = {
  blockbookServers: ['wss://pivx-eusa1.edge.app']  // eusa1
}

const engineInfo = {
  serverConfigs: [{ type: 'blockbook-ws', url: 'wss://pivx-wusa1.edge.app' }]  // wusa1
}
```

Configuration values that refer to the same resource must be synchronized. Consider extracting shared constants:

```typescript
const PIVX_BLOCKBOOK_SERVER = 'wss://pivx-eusa1.edge.app'

const deprecatedDefaultSettings = {
  blockbookServers: [PIVX_BLOCKBOOK_SERVER]
}

const engineInfo = {
  serverConfigs: [{ type: 'blockbook-ws', url: PIVX_BLOCKBOOK_SERVER }]
}
```

