---
name: fix-eslint
description: Fix ESLint warnings by applying documented patterns. Use when addressing @typescript-eslint/no-deprecated warnings for NavigationBase, RouteProp, or other deprecated types in edge-react-gui.
---

<goal>Resolve ESLint `@typescript-eslint/no-deprecated` warnings by replacing deprecated type references with their non-deprecated equivalents.</goal>

<rules description="Non-negotiable constraints.">
<rule id="tsc-after-fix">Run `npx tsc --noEmit` after every type change to verify no new type errors are introduced.</rule>
<rule id="no-suppress">Do not suppress deprecation warnings with `eslint-disable` comments. Fix the underlying type reference.
Exception: `NavigationBase` deprecation in shared cross-navigator code (Categories C, D, F below) is accepted — not suppressed, genuinely not fixable without a broader v7 navigation migration. When the fix scope is too broad, add a TODO comment documenting the required migration pattern and accept the warning.</rule>
<rule id="scope-control">Only modify files with deprecation warnings. Do not refactor downstream declarations unless required for the fix to compile.</rule>
</rules>

<patterns>

<pattern id="navigation-base" rule="@typescript-eslint/no-deprecated" symbol="NavigationBase">
`NavigationBase` is a flat navigation type hack in `routerTypes.tsx` that unions all navigator param lists (`RootParamList & DrawerParamList & EdgeAppStackParamList & ...`) to pretend the app is flat. It is deprecated because it tracks **react-navigation v7 breaking changes**:

1. `navigate()` no longer crosses nested navigator boundaries at runtime.
2. `navigate()` no longer goes back to an existing screen to update params — use `popTo()` or `navigate(screen, params, { pop: true })` instead.

v7 provides `navigateDeprecated()` and `navigationInChildEnabled` as temporary bridges, both removed in v8. **Do NOT create non-deprecated aliases** (like `AppNavigation`) — this hides a real migration requirement.

Fix `NavigationBase` deprecation by identifying which category the usage falls into:

**Category A — Pass-through props** (component accepts `NavigationBase` only to forward it to children or actions):
- Fix: Remove the `navigation` prop. Callers already have navigation in scope. If the child needs navigation, it should use `useNavigation()` or accept specific callbacks.
```typescript
// Before — CancellableProcessingScene accepts navigation to forward to onError
interface Props { navigation: NavigationBase; onError: (nav: NavigationBase, err: unknown) => void }

// After — remove navigation prop, callers handle navigation in callbacks
interface Props { onError: (err: unknown) => Promise<void> }
```

**Category B — Direct navigation in non-scene components** (component accepts `NavigationBase`, calls `navigate()`/`push()` directly):
- Fix: Replace `navigation: NavigationBase` prop with `useNavigation()` hook typed to the navigator context the component lives in. Or replace with specific navigation callbacks from the parent scene.
```typescript
// Before — BalanceCard accepts NavigationBase, calls navigate directly
interface Props { navigation: NavigationBase }
const BalanceCard: React.FC<Props> = props => {
  props.navigation.push('send2', { walletId, tokenId })
}

// After (option 1) — useNavigation hook
const BalanceCard: React.FC<Props> = props => {
  const navigation = useNavigation<EdgeAppSceneProps<'home'>['navigation']>()
  navigation.push('send2', { walletId, tokenId })
}

// After (option 2) — navigation callbacks
interface Props { onSend: (walletId: string, tokenId: EdgeTokenId) => void }
```
- If the fix would cascade to many callers or require determining the correct navigator context across multiple usages, add a `// TODO: Replace NavigationBase with useNavigation() or callbacks. Requires v7 navigation migration.` comment and move on.

**Category C — Shared action/thunk functions** (functions in `src/actions/` accept `NavigationBase`):
- Fix: Invert control. Replace the `navigation: NavigationBase` parameter with a callback for the navigation action the function needs.
```typescript
// Before — function navigates internally
function activateWalletTokens(navigation: NavigationBase, wallet, tokenIds): ThunkAction<Promise<void>> {
  // ... calls navigation.navigate('editToken', ...) internally
}

// After — caller provides the navigate action
function activateWalletTokens(wallet, tokenIds, onNavigate: (route: string, params: object) => void): ThunkAction<Promise<void>> {
  // ... calls onNavigate('editToken', ...) instead
}
```
- Simpler alternative for single-navigate functions: Return the target route + params instead of navigating; let the caller dispatch.
- If the function has many navigate calls to different screens or the refactoring would touch many callers, add a `// TODO: Remove NavigationBase dependency. Requires inversion of navigation control for v7 migration.` comment and move on.

**Category D — Shared modal components** (modals accept `NavigationBase`, navigate after user interaction):
- Fix: Modal returns a result via Airship bridge resolve; caller handles navigation based on the result. Or modal accepts navigation callbacks.
- If the modal's navigation logic is complex (multiple paths), add a comment and move on.

**Category E — Scene component casts** (`navigation as NavigationBase`):
- These casts exist because the scene passes navigation to a Category A-D consumer.
- Fix: No direct fix needed — casts disappear automatically when the consumer is migrated.
- If the scene has its own `NavigationBase` usage unrelated to shared code, apply Category B fix.

**Category F — Service components** (non-scene services: `DeepLinkingManager`, `AccountCallbackManager`, etc.):
- These are the broadest migration cases. Always add: `// TODO: Remove NavigationBase dependency. Requires broader v7 navigation migration for service-level navigation.`
- Do not attempt to fix these incrementally — they are cross-cutting and require dedicated migration work.
</pattern>

<pattern id="route-prop" rule="@typescript-eslint/no-deprecated" symbol="RouteProp">
Replace deprecated `RouteProp<'routeName'>` with the scene-specific route type.

```typescript
// Before
import type { RouteProp } from '../../types/routerTypes'
const route = useRoute<RouteProp<'walletDetails'>>()

// After
import type { WalletsTabSceneProps } from '../../types/routerTypes'
const route = useRoute<WalletsTabSceneProps<'walletDetails'>['route']>()
```

Choose the scene props type that matches the navigator the component lives in:
- `WalletsTabSceneProps` for walletList, walletDetails, transactionList, transactionDetails
- `EdgeAppSceneProps` for routes in EdgeAppStackParamList
- `SwapTabSceneProps` for swap routes
- `BuySellTabSceneProps` for buy/sell routes
- `RootSceneProps` for login, home, etc.
</pattern>

</patterns>
