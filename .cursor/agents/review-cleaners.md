---
name: review-cleaners
description: Reviews code for cleaner library usage and data validation patterns. Use when reviewing files that handle external data (API responses, disk reads).
---

Review the branch/pull request in context for cleaner usage conventions.

## Context Expected

You will receive:
- Repository name
- Branch name
- List of changed files to review

## How to Review

1. Read the changed files provided in context
2. Look for `fetch`, API calls, file reads, or external data sources
3. Verify cleaners are applied before data is used
4. Check for type/cleaner duplication
5. Report findings with specific file:line references

---

## Clean All External Data

All network requests and data reads from disk must be cleaned with the cleaners library. Code must access the cleaned values, not the original raw/untyped data object.

---

## Let Cleaners Handle Parsing

Use cleaners for JSON parsing instead of double-parsing:

```typescript
// Incorrect
const data = JSON.parse(response)
const cleaned = asMyType(data)

// Correct - let cleaners handle it
const asMyResponse = asJSON(asObject({
  field: asString
}))
const cleaned = asMyResponse(response)
```

---

## No Duplicate Types

Types should be derived from cleaners using `ReturnType` syntax. Do not duplicate type definitions:

```typescript
// Incorrect - duplicated type
interface MyData {
  name: string
  value: number
}
const asMyData = asObject({
  name: asString,
  value: asNumber
})

// Correct - derive type from cleaner
const asMyData = asObject({
  name: asString,
  value: asNumber
})
type MyData = ReturnType<typeof asMyData>
```

---

## Remove Unused Fields

Remove or comment out any fields in a cleaner that are unused in the codebase.

---

## asOptional Handles Both Undefined and Null

Despite the name, `asOptional` accepts both `undefined` AND `null` values. This is non-intuitive but useful:

```typescript
// asOptional accepts: missing field, undefined, or null
const asResponse = asObject({
  data: asOptional(asString)  // Works for { data: null }
})

// These all pass:
asResponse({})                    // data is undefined
asResponse({ data: undefined })   // data is undefined
asResponse({ data: null })        // data is null (converted to undefined by default)
asResponse({ data: 'hello' })     // data is 'hello'
```

When you need to preserve the distinction between `null` and `undefined`:

```typescript
// To preserve explicit null values from API
const asResponse = asObject({
  data: asOptional(asEither(asNull, asString), null)
  // Second arg is default: null if missing/undefined, otherwise the actual value
})
```

---

## New Fields Must Be Optional for Backward Compatibility

When adding new fields to cleaners that validate persisted data (files saved to disk, transaction metadata, etc.), always use `asOptional` to handle existing data that doesn't have the new field:

```typescript
// Incorrect - breaks loading existing transaction files
const asEdgeTxSwap = asObject({
  orderId: asOptional(asString),
  payoutTokenId: asEdgeTokenId  // BUG: Old files don't have this field
})

// Correct - handles old data gracefully
const asEdgeTxSwap = asObject({
  orderId: asOptional(asString),
  payoutTokenId: asOptional(asEdgeTokenId)  // Old files load successfully
})
```

If the field is truly required, first add it as optional and include a migration path for existing data. Types can reflect the optional nature:

```typescript
// In cleaners (backward compatible)
const asEdgeTxSwap = asObject({
  payoutTokenId: asOptional(asEdgeTokenId)
})

// Type reflects optional nature - GUI handles missing values
type EdgeTxSwap = ReturnType<typeof asEdgeTxSwap>
// payoutTokenId?: EdgeTokenId
```

**Rule:** Any field added to a cleaner for persisted data MUST be wrapped with `asOptional` unless migration code is included.
