---
name: review-state
description: Reviews code for state management patterns including Redux, module-level state, and account data storage. Use when reviewing files with useState, useSelector, or data persistence.
---

Review the branch/pull request in context for state management conventions.

## Context Expected

You will receive:
- Repository name
- Branch name
- List of changed files to review

## How to Review

1. Read the changed files provided in context
2. Look for useState, useSelector, module-level variables, disklet usage
3. Verify state management follows conventions
4. Report findings with specific file:line references

---

## Don't Duplicate Redux State Locally

Don't track state locally in components when it should come from a centralized system:

```typescript
// Incorrect - duplicates permission state locally
const [cameraPermission, setCameraPermission] = useState(reduxCameraPermission)
// This state becomes stale when redux updates

// Correct - fix at the source (permissions manager) to update redux
// Then components just read from redux
const cameraPermission = useSelector(state => state.permissions.camera)
```

---

## Module-Level Cache Bugs

Module-level cached state that doesn't reset on logout/login is a common bug pattern. When caching account-specific data at module level, ensure it's cleared on logout:

```typescript
// Bug-prone pattern
let localAccountSettings: Settings | null = null
let readSettingsFromDisk = false

// If readSettingsFromDisk becomes true for User A,
// User B will get User A's cached settings!
```

### Clearing Session State

For module-level caches, export a clear function and call it on logout:

```typescript
// In the module with cached state
let cachedBrands: Brand[] | null = null

export const clearBrandCache = () => {
  cachedBrands = null
}

// In logout action
import { clearBrandCache } from './brandCache'

const handleLogout = async () => {
  clearBrandCache()
  // ... other cleanup
}
```

---

## Settings Belong in Redux

Local account settings should go in redux, not separate module-level caches:

> "Redux is the perfect place for globally-available information like account settings, and the local settings definitely belong in there."

---

## Use DataStore API for Account Data

NEVER add random files to account synced storage directly. Use the plugin storage API:

```typescript
// Incorrect - leaks info through unencrypted filenames
await account.localDisklet.setText('my-file.json', data)

// Correct - encrypts filenames
await account.dataStore.setItem('pluginId', 'keyName', data)
```

Account filenames are stored in plaintext, which leaks information the server shouldn't see. The `dataStore` API encrypts filenames.

---

## Non-Account Data

For data that isn't account-specific (like cached catalogs), use the global disklet:

```typescript
// For non-account-specific data
const disklet = state.core.disklet
// or
const disklet = makeReactNativeDisklet()
```

---

## Data Format Migrations

When changing storage formats, always include migration code for existing data:

```typescript
// When changing from:
await dataStore.setItem('identities', allIdentities)
// To:
await dataStore.setItem('identity-' + id, identity)

// Include migration:
const legacyIdentities = await dataStore.getItem('identities')
if (legacyIdentities != null) {
  for (const identity of legacyIdentities) {
    await dataStore.setItem('identity-' + identity.id, identity)
  }
  await dataStore.deleteItem('identities')
}
```
