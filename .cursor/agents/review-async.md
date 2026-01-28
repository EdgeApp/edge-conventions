---
name: review-async
description: Reviews code for async patterns including timers, data loading, and background services. Use when reviewing files with setInterval, async functions, or service components.
---

Review the branch/pull request in context for async pattern conventions.

## Context Expected

You will receive:
- Repository name
- Branch name
- List of changed files to review

## How to Review

1. Read the changed files provided in context
2. Look for setInterval, async data loading, background work
3. Verify async patterns follow conventions
4. Report findings with specific file:line references

---

## Never Use setInterval

Always use `makePeriodicTask` instead, especially when async work is involved:

```typescript
// Incorrect
setInterval(() => fetchData(), 5000)

// Correct
const task = makePeriodicTask(async () => {
  await fetchData()
}, 5000)
task.start()
// ... later
task.stop()
```

---

## Use TanStack Query or useAsyncValue

For async data loading in components, use TanStack Query:

```typescript
import { useQuery } from '@tanstack/react-query'

const { data, isLoading } = useQuery({
  queryKey: ['myData'],
  queryFn: fetchMyData
})
```

Or use existing `useAsyncValue` hook. Don't re-implement async loading patterns.

---

## Background Services

Background services go in `components/services/` directory:

> "If we did want a persistent background service, it would go in components/services. Making it a component means it gets mounted/unmounted cleanly when we log in/out, and we can also see all the background stuff in one place."

Avoid too much background work. Consider:
- Triggering only when the user has pending items
- Running only when on the relevant scene

---

## Prevent Concurrent Execution

Use a helper to prevent duplicate parallel calls when a function can be triggered multiple times (e.g., button presses, retries):

```typescript
// Helper to ensure only one execution at a time
function runOnce<T>(fn: () => Promise<T>): () => Promise<T | undefined> {
  let running = false
  return async () => {
    if (running) return
    running = true
    try {
      return await fn()
    } finally {
      running = false
    }
  }
}

// Usage
const handleSubmit = runOnce(async () => {
  await submitForm()
})
```

This prevents race conditions from multiple simultaneous calls to the same async function.

---

## Polling Race Conditions

When implementing polling that can be cancelled, ensure the cancel flag is checked after each async operation:

```typescript
// Incorrect - race condition if cancelled during poll interval
const pollForStatus = async (cancel: { cancelled: boolean }) => {
  while (!cancel.cancelled) {
    const status = await checkStatus()
    if (status === 'complete') return status
    await sleep(2000)
    // BUG: If cancelled during sleep, still continues
  }
}

// Correct - check cancel after every await
const pollForStatus = async (cancel: { cancelled: boolean }) => {
  while (!cancel.cancelled) {
    const status = await checkStatus()
    if (cancel.cancelled) return
    if (status === 'complete') return status
    await sleep(2000)
  }
}
```

---

## Refresh State in Async Callbacks

When a timeout or async callback needs current state, read it fresh inside the callback rather than capturing it in a closure:

```typescript
// Incorrect - captured state becomes stale
const { wallets } = props.state  // Captured at setup time
setTimeout(() => {
  for (const walletId of walletIds) {
    const wallet = wallets[walletId]  // Stale - may not reflect changes
    wallet.doSomething()
  }
}, 15000)

// Correct - read fresh state in callback
setTimeout(() => {
  const { wallets } = props.state  // Fresh read
  for (const walletId of walletIds) {
    const wallet = wallets[walletId]
    if (wallet == null) continue  // Guard against removed wallets
    wallet.doSomething()
  }
}, 15000)
```

State captured in closures doesn't update when the source changes. This is especially important for timeouts and interval callbacks that run much later.

---

## Clean Up Timeouts on Shutdown

When using `setTimeout` in services or engines that can be stopped, track pending timeouts and clear them on shutdown:

```typescript
// Incorrect - timeouts persist after engine stops
class MyEngine {
  async processItem(id: string) {
    try {
      await this.fetch(id)
    } catch (error) {
      // BUG: This timeout runs even after killEngine() is called
      setTimeout(() => this.processItem(id), 5000)
    }
  }

  async killEngine() {
    this.cache.clear()  // Timeouts still fire after this!
  }
}

// Correct - track and clear pending timeouts
class MyEngine {
  private pendingTimeouts: Set<ReturnType<typeof setTimeout>> = new Set()

  async processItem(id: string) {
    try {
      await this.fetch(id)
    } catch (error) {
      const timeoutId = setTimeout(() => {
        this.pendingTimeouts.delete(timeoutId)
        this.processItem(id)
      }, 5000)
      this.pendingTimeouts.add(timeoutId)
    }
  }

  async killEngine() {
    // Clear all pending timeouts before cleanup
    for (const timeoutId of this.pendingTimeouts) {
      clearTimeout(timeoutId)
    }
    this.pendingTimeouts.clear()
    this.cache.clear()
  }
}
```

**Rule:** Any `setTimeout` in a service that has a shutdown/cleanup method must be tracked and cleared on shutdown to prevent callbacks from executing on stale/cleared state.
