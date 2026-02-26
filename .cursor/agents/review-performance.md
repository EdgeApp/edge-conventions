---
name: review-performance
description: Reviews code for performance patterns that affect UI responsiveness, especially RN JS thread load, YAOB bridge volume, and engine callback redundancy. Use when reviewing engine code, useWatch/withWallet, bridge/throttle, or navigation-related changes.
---

Review the branch/pull request in context for performance conventions that affect wallet scene transitions and steady-state UI responsiveness.

## Context Expected

You will receive:
- Repository name
- Branch name
- List of changed files to review

## How to Review

1. Read the changed files provided in context
2. Look for engine callbacks, useWatch/subscription patterns, bridge/throttle usage, and navigation
3. Verify changes avoid redundant callbacks and broad subscriptions that flood the RN JS thread
4. Report findings with specific file:line references

---

## Avoid Redundant Engine Callbacks

Engine callbacks (onSyncStatusChanged, onBlockHeightChanged, onTransactions, onNewTokens, etc.) become YAOB bridge messages and Redux dispatches. Each one adds work on the RN JS thread. Do not fire when the value has not changed.

### onSyncStatusChanged — Gate by Ratio

Engines that are already fully synced (ratio=1.0) must not keep firing onSyncStatusChanged. Guard with last-value comparison:

```typescript
// Incorrect - fires every poll even when ratio unchanged
this.currencyEngineCallbacks.onSyncStatusChanged({ ratio })

// Correct - only fire when ratio actually changed
if (ratio !== this.lastSyncRatio) {
  this.lastSyncRatio = ratio
  this.currencyEngineCallbacks.onSyncStatusChanged({ ratio })
}
```

### onBlockHeightChanged — Prefer onSeenTx / Direct Confirmations

Accountbased engines should set confirmations directly on transactions and use onSeenTxCheckpoint instead of calling onBlockHeightChanged every block. Every onBlockHeightChanged triggers core-js to iterate all transactions for that wallet. If confirmations are set on the transaction (e.g. 'confirmed' | 'unconfirmed' | number), core-js can skip that work.

- Set `confirmations: 'confirmed' | 'unconfirmed' | number` on EdgeTransaction in onTransactions
- Call onSeenTxCheckpoint with block height when sync advances
- Do not call onBlockHeightChanged for accountbased engines that set confirmations

UTXO plugins already set confirmations in toEdgeTransaction; they should not wire BLOCK_HEIGHT_CHANGED to callbacks.onBlockHeightChanged (internal event is fine for unconfirmed tx checks).

### onTransactions — Skip Emit for Unchanged / Already-Known

Do not emit TRANSACTIONS (or call onTransactions) when the transaction already exists and has not changed. In UTXO processAddressForTransactions, only emit if the tx is new or blockHeight changed:

```typescript
// Correct - only emit when tx is new or changed
if (existingTx == null || existingTx.blockHeight !== tx.blockHeight) {
  common.emitter.emit(EngineEvent.TRANSACTIONS, [{ isNew, transaction: edgeTx }])
}
```

In core-js currency-wallet-callbacks, gate the Redux CURRENCY_ENGINE_CHANGED_TXS dispatch so it does not fire when compare() filters out all transactions (no changed/created/txidHashes).

### onNewTokens — Gate by Actual Change

Only call onNewTokens when the detected token set has changed. Persist last-reported set (e.g. in walletLocalData as detectedTokenIds) and compare before calling:

```typescript
// Correct - gate by sorted comparison, persist for cross-session
protected reportDetectedTokens(tokenIds: string[]): void {
  const sorted = [...tokenIds].sort()
  if (sorted.length === this.lastDetectedTokenIds.length &&
      sorted.every((id, i) => id === this.lastDetectedTokenIds[i])) return
  this.lastDetectedTokenIds = sorted
  this.walletLocalData.detectedTokenIds = sorted
  this.currencyEngineCallbacks.onNewTokens(sorted)
}
```

Call sites (EthereumNetwork, AlgorandEngine, SolanaEngine, etc.) should use this helper instead of calling onNewTokens(detectedTokenIds) directly on every sync cycle.

### onStakingStatusChanged — Gate by Value Change

Do not call onStakingStatusChanged on every poll when status is unchanged. Compare JSON or key fields to last value and only fire when different (e.g. TronEngine, FioEngine).

### onSeenTxCheckpoint — Only on Advancement

Only call onSeenTxCheckpoint when the new checkpoint is higher than the previous one (e.g. MoneroEngine checkTransactionsInnerLoop). Do not fire on every loop when checkpoint is unchanged.

### Empty or No-Op Callbacks

Do not emit transaction callbacks with count=0 when there are no new or changed transactions (e.g. Monero empty onTransactions). Gate so only meaningful updates are sent.

---

## EngineEmitter and Event Deduplication

The EngineEmitter (and equivalent patterns) should suppress duplicate emissions when the value has not changed:

- BLOCK_HEIGHT_CHANGED: suppress if blockHeight === lastBlockHeight
- WALLET_BALANCE_CHANGED: suppress if balance === lastBalance
- ADDRESSES_CHECKED: suppress if ratio === lastRatio (and avoid resetting progress to 0 on every start() when wallet was already fully synced)

UTXO: If processedPercent was 1 (fully synced), do not reset to 0 on start(); skip the 0%→100% address-checked walk to avoid hundreds of redundant ADDRESSES_CHECKED events.

---

## Selective YAOB / useWatch Subscription

Components that only care about a single wallet must not subscribe to the entire account.currencyWallets map; that causes re-renders on any wallet change across all wallets.

- Prefer per-wallet useWatch(wallet, 'balance') or specific keys instead of useWatch(account, 'currencyWallets')
- Use useMemo or selector patterns so the component does not re-render when the specific wallet data has not changed
- In wallet list, consider subscribing only to wallets in the viewport

Locations: withWallet.tsx, WalletListSwipeable*, WalletDetailsScene, useWatch usage.

---

## Redux Dispatch Only When State Actually Changed

In core-js (e.g. currency-wallet-callbacks), avoid dispatching CURRENCY_ENGINE_CHANGED_* when the derived state has not changed. Each dispatch triggers the pixie watcher and yaob:update(walletApi). Gate dispatches on actual changes (e.g. changed/created/txidHashes length or content).

---

## Summary Checklist

- [ ] onSyncStatusChanged / onBlockHeightChanged / onNewTokens / onStakingStatusChanged / onSeenTxCheckpoint only fire when value changed
- [ ] onTransactions / TRANSACTIONS not emitted for already-known unchanged txs
- [ ] No empty or no-op transaction/sync callbacks (e.g. count=0 when nothing new)
- [ ] EngineEmitter or equivalent deduplicates BLOCK_HEIGHT_CHANGED, WALLET_BALANCE_CHANGED, ADDRESSES_CHECKED
- [ ] useWatch scoped to the minimal data needed (per-wallet, not whole currencyWallets)
- [ ] Redux dispatch gated so it does not run when compare() or logic shows no user-visible change
