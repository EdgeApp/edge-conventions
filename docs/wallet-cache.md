# Wallet Cache Production Plan

## Goal

Implement a wallet cache in edge-core-js with lazy engine instantiation. Users should be able to log in and see their wallets (with balances, names, etc.) without any calls to `makeCurrencyEngine`. Engines should only be instantiated when the GUI actually needs to interact with a wallet.

## Requirements

1. **Default behavior (no settings)**: Wallet caching is enabled by default with no configuration required.

2. **Auto-save cache (throttled)**: When any cached values change (balances, name, tokens, etc.), write the cache to disk. Throttle writes to at most once every 5 seconds.

3. **Load cached wallets on login**: On login, load cached wallet data and create wallet objects with cached values before any engine calls.

4. **Lazy engine instantiation**: Do NOT call `makeCurrencyEngine` until the GUI calls a method that requires the engine (e.g., `getFreshAddress`, `signTx`, `broadcastTx`).

5. **Transparent engine replacement**: When a method requiring the engine is called:
   - Call `makeCurrencyEngine` and `startEngine` on the real plugin
   - Pass through to the real engine method
   - Mutate the cached wallet object in-place with real capabilities

## Implementation Steps

#### Step 1: Create cache schema and storage

Define the wallet cache schema and implement save/load functionality.

**Schema** (`cache-wallet-cleaners.ts`):
```typescript
export const asCachedWallet = asObject({
  id: asString,
  name: asOptional(asString),
  type: asString,
  created: asOptional(asDate),
  balances: asOptional(asObject(asString)), // tokenId -> balance string
  blockHeight: asOptional(asNumber),
  transactionCount: asOptional(asNumber),
  addresses: asOptional(asArray(asString)),
  enabledTokenIds: asOptional(asArray(asString)),
  paused: asOptional(asBoolean)
})

export const asCachedWalletFile = asObject({
  wallets: asArray(asCachedWallet)
})
```

**Storage location**: Account-level storage (e.g., `walletCache.json`)

#### Step 2: Implement cache save/load with throttling

**Save** (`cache-wallet-saver.ts`):
- Write cache to account-level storage
- Include all wallet properties listed in schema
- Read balances, `transactionCount`, `addresses`, `enabledTokenIds`, `paused` from wallet state
- Implement 5-second throttle (at most one write per 5 seconds)
- Add observer pattern to trigger save when cached values change

**Load** (`cache-wallet-loader.ts`):
- Read cache file on login
- Return cached wallet data to populate wallet objects
- Initialize wallet state in Redux for cached wallets

#### Step 3: Lazy engine instantiation

- Modify `currency-wallet-pixie.ts` to delay `makeCurrencyEngine` call
- Cached wallet methods that need engine should trigger instantiation
- Track which wallets have real engines vs cached-only

#### Step 4: Engine method passthrough with lazy instantiation

- When a cached wallet method is called that needs the engine:
  1. Await `makeEngine` (use promise lock to prevent duplicate calls)
  2. Trigger `startEngine` (fire-and-forget, don't block)
  3. Call the real engine method
  4. Return the real result
- Store engine reference for subsequent calls

#### Step 5: In-place wallet mutation

- Mutate the cached wallet object in-place as methods become available
- No need to replace references - the same object gains real capabilities
- GUI components holding wallet references continue to work seamlessly

## Wallet Methods and Cached Values

The cached wallet exposes the same `EdgeCurrencyWallet` interface. Most read-only properties are Yaob-bridged values that can be served directly from the cache.

### Static Read-Only Properties (always cached)

These properties are available immediately from the cache without engine initialization:

- `id`
- `name`
- `created`
- `type`
- `currencyConfig`
- `currencyInfo`
- `balanceMap`
- `balances`
- `blockHeight`
- `syncRatio` — Initializes to `0` for cached wallets

### Wallet Methods

| Method | Behavior | Notes |
|--------|----------|-------|
| `getNumTransactions()` | Cache first | Return cached `transactionCount`; if not cached, trigger engine start |
| `getAddresses()` | Cache first | Return cached `addresses`; if not cached, trigger engine start. Cache the result when called. |
| `getTransactions()` | Engine required | Triggers engine start |
| `streamTransactions()` | Engine required | Triggers engine start |
| `getFreshAddress()` | Engine required | Triggers engine start |
| `makeSpend()` | Engine required | Triggers engine start |
| `signTx()` | Engine required | Triggers engine start |
| `broadcastTx()` | Engine required | Triggers engine start |
| `saveTx()` | Engine required | Triggers engine start |
| `startEngine()` | Engine required | Explicit engine start |
| `stopEngine()` | No-op if not started | Safe to call on cached-only wallets |
| `changePaused()` | Engine required | Triggers engine start |
| `resyncBlockchain()` | Engine required | Triggers engine start |
| `getMaxSpendable()` | Engine required | Triggers engine start |
| `sweepPrivateKeys()` | Engine required | Triggers engine start |
| `signBytes()` | Engine required | Triggers engine start |
| `accelerate()` | Engine required | Triggers engine start |
| `saveTxMetadata()` | Engine required | Needs transaction from plugin |

### Methods That Work Without Engine

These methods can operate on cached/local data without engine initialization:

| Method | Notes |
|--------|-------|
| `renameWallet()` | Updates local wallet name |
| `setFiatCurrencyCode()` | Updates local fiat preference |
| `changeEnabledTokenIds()` | Updates local token settings |
| `encodeUri()` | Uses currencyInfo from plugin |
| `parseUri()` | Uses currencyInfo from plugin |

### Watch Methods

Watch methods (`watch('balance', ...)`, etc.) fire immediately with cached values when subscribed. As the engine syncs and updates values, watch callbacks fire again with updated data. This provides instant UI feedback while real data loads in the background.

## Unstarted vs Started Cached Wallets

A cached wallet can be in one of two states: **unstarted** or **started**. This distinction affects how engine methods behave.

### Unstarted Cached Wallet

A wallet that is cached but has not yet been started (via `startEngine()`):

- **Cached data**: All cached properties (balances, name, addresses, etc.) are available immediately
- **Engine method calls**: Calling an engine-requiring method (e.g., `getFreshAddress`, `makeSpend`) will call `makeEngine()` but **NOT** `startEngine()`. The engine is created but not syncing.
- **Sync status**: `syncRatio` remains `0` until the wallet is started

### Started Cached Wallet

Once a wallet is started (explicitly via `startEngine()`):

- **Engine methods**: Call `makeEngine()` (if not already created) and trigger `startEngine()` (fire-and-forget)
- **Normal operation**: All standard wallet behavior applies

### State Transitions

```
[Cached + Unstarted]
        |
        | startEngine() called explicitly
        v
[Cached + Started] --> normal wallet operation
```

## Design Decisions

1. **Wallet reference replacement**: Mutate the cached wallet object in-place. This preserves GUI references and avoids stale pointers.

2. **Engine startup blocking**:
   - All engine method calls **block on `makeEngine`** (must complete before method can execute)
   - For **started wallets**: engine method calls trigger `startEngine` (fire-and-forget, non-blocking)
   - For **unstarted wallets**: engine method calls do NOT trigger `startEngine` — only `makeEngine` is called
   - This allows methods like `getFreshAddress` to return quickly once the engine is created, without waiting for full sync

3. **Error handling**: If engine instantiation fails, keep showing cached data. Log the error but don't disrupt the user experience.

4. **Concurrent calls**: Use a promise-based lock pattern. The first call to any engine-requiring method creates a shared promise for `makeEngine`. All concurrent calls await that same promise, ensuring `makeEngine` is only called once per wallet.

5. **Cache invalidation**: The cache is never invalidated. It always reflects the last-known state of each wallet. When engines start, they update the cache with fresh data, which is then persisted via the auto-save mechanism.

6. **Load order**: All cached wallets must be fully loaded (as proxy/cached wallet objects) before `makeCurrencyEngine` or `startEngine` is called on any of them. This ensures the GUI has access to all wallet references immediately on login, and prevents race conditions during initialization.

```typescript
// Pseudocode for lazy engine pattern
class CachedWallet {
  private enginePromise: Promise<EdgeCurrencyEngine> | undefined
  private started: boolean = false

  private async ensureEngine(): Promise<EdgeCurrencyEngine> {
    if (this.enginePromise == null) {
      this.enginePromise = this.createEngine()
    }
    return this.enginePromise
  }

  private async createEngine(): Promise<EdgeCurrencyEngine> {
    const engine = await plugin.makeCurrencyEngine(...)
    // Only trigger startEngine if wallet is in started state
    if (this.started) {
      engine.startEngine().catch(err => log.error(err))
    }
    return engine
  }

  // Called when wallet transitions to started state
  async startEngine(): Promise<void> {
    this.started = true
    if (this.enginePromise != null) {
      const engine = await this.enginePromise
      engine.startEngine().catch(err => log.error(err))
    }
  }

  async getFreshAddress(): Promise<EdgeFreshAddress> {
    const engine = await this.ensureEngine()
    return engine.getFreshAddress()
  }
}
```

## Special Cases

### First Login (No Cache)

On first login when no cache exists, all methods route directly to real engines. Call `makeCurrencyEngine()` and `startEngine()` for all wallets immediately. The cache will be populated as engines sync and the auto-save mechanism persists the data.

### New Wallet Creation

When a user creates a new wallet, call `makeCurrencyEngine()` and `startEngine()` immediately. There is no cache to load, so the wallet operates normally from the start. The cache will be populated as the engine syncs.

### Multi-Device Usage

Each device has its own completely separate cache instance and storage. The cache on one device is irrelevant to another device. When a user logs in on a new device, they start with no cache (see "First Login" above). Subsequent logins on that device use that device's local cache.

### `otherMethods` Handling

Currency plugins may expose an `otherMethods` object with plugin-specific functions. To support these with lazy instantiation:

**Save** (when writing cache):
- Inspect the `otherMethods` object on the engine
- Write the function names to the cache (not the implementations)

**Load** (when reading cache):
- Create stub functions for each cached method name
- When any stub is called, trigger `makeCurrencyEngine` and `startEngine`
- Pass through the function call to the real `otherMethods` implementation

On first login (no cache), engines are started immediately, so `otherMethods` are available directly. The function names are then cached for subsequent logins.

### Deleted Wallets

When a wallet is deleted, its cache entry should also be deleted from the cache file.

### Archived Wallets

Archived wallets should be deleted from the cache. They do not show in the UI, so there is no benefit to caching them. When a wallet is unarchived, it will be treated as a new wallet (engine started immediately, cache populated as it syncs).

### Paused Wallets

Paused wallets should be cached with their paused status saved (see `paused` field in schema above). On cache load, restore the paused state. A paused cached wallet remains paused until explicitly unpaused.

### Disklet Objects

The wallet object includes disklet objects with methods (e.g., `localDisklet`, `disklet`). These should NOT be cached — initialize disklet objects as they would normally be initialized for an uncached wallet. Disklets provide file system access and must be available immediately regardless of engine state.

## Testing Strategy

Use the `debug-edge` skill to test changes in the full Edge app on iOS simulator.

### Setup

1. Set `DEBUG_CORE: true` in `edge-react-gui/env.json`
2. In terminal 1: Run `yarn && yarn start` in `edge-core-js` to start the debug server
3. In terminal 2: Run `yarn start` in `edge-react-gui` to start Metro bundler
4. Build and launch the app using the `user-xcodebuild` MCP tools

### Debug Logging

Add debug logs using `log.warn()` in edge-core-js to track wallet cache behavior:

```typescript
log.warn('Wallet cache loaded', { walletId, cached: true })
log.warn('Engine instantiated', { walletId, trigger: 'getFreshAddress' })
```

These messages appear in the Metro bundler terminal output.

### Verification Checklist

1. **Login speed**: Cached wallets appear immediately on login without waiting for engine startup
2. **Lazy instantiation**: Engines only start when engine-requiring methods are called (verify via logs)
3. **Cache persistence**: Log out and back in — cached values should persist
4. **Paused wallets**: Verify paused state is restored from cache
5. **New wallets**: Creating a new wallet starts engine immediately
