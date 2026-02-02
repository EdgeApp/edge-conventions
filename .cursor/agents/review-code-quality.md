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
  body: JSON.stringify(body)
})
```

This pattern catches type errors at compile time when the API contract changes.

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

## No Local Path Dependencies

Don't use local file paths in package.json dependencies:

```json
// Incorrect - local path dependency
{
  "dependencies": {
    "my-package": "file:../my-package"
  }
}

// Correct - use published version or git URL
{
  "dependencies": {
    "my-package": "^1.0.0"
  }
}
```

Local paths break builds for other developers and CI systems.

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

## Use Local Helpers for Amount Conversions

Avoid async wallet API calls for conversions since they cross an expensive bridge. Use local synchronous helpers instead:

```typescript
// Incorrect - async bridge call for simple conversion
const amount = await wallet.nativeToDenomination(nativeAmount, currencyCode)

// Correct - use local helper with biggystring
import { div } from 'biggystring'
import { getExchangeDenom } from '../selectors/DenominationSelectors'

const { multiplier } = getExchangeDenom(wallet.currencyConfig, tokenId)
const exchangeAmount = div(nativeAmount, multiplier, DECIMAL_PRECISION)
```

For native-to-exchange conversion, always specify precision to avoid integer truncation:

```typescript
// Incorrect - integer division truncates decimals
const amount = div(nativeAmount, multiplier)  // 50000000 / 100000000 = 0

// Correct - specify decimal precision
const DECIMAL_PRECISION = 18
const amount = div(nativeAmount, multiplier, DECIMAL_PRECISION)  // "0.5"
```

The `getExchangeDenom` helper synchronously reads from `currencyConfig` which is already available locally.

---

## Don't Hand-Roll Standard Operations

Use established libraries instead of implementing standard algorithms:

```typescript
// Incorrect - hand-rolled base64 encoding
const toBase64 = (data: Uint8Array): string => {
  let result = ''
  for (let i = 0; i < data.length; i += 3) {
    // ... manual base64 implementation
  }
  return result
}

// Correct - use rfc4648 library
import { base64 } from 'rfc4648'
const encoded = base64.stringify(data)
const decoded = base64.parse(encodedString)
```

Hand-rolled implementations:
- May have subtle bugs
- Lack test coverage
- Add maintenance burden
- Often miss edge cases the library handles

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

