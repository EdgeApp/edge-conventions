---
name: fix-eslint
description: Fix ESLint warnings by applying documented patterns. Use when addressing @typescript-eslint/no-deprecated warnings for NavigationBase, RouteProp, or other deprecated types in edge-react-gui.
---

<goal>Resolve ESLint `@typescript-eslint/no-deprecated` warnings by replacing deprecated type references with their non-deprecated equivalents.</goal>

<rules description="Non-negotiable constraints.">
<rule id="tsc-after-fix">Run `npx tsc --noEmit` after every type change to verify no new type errors are introduced.</rule>
<rule id="no-suppress">Do not suppress deprecation warnings with `eslint-disable` comments. Fix the underlying type reference.</rule>
<rule id="scope-control">Only modify files with deprecation warnings. Do not refactor downstream declarations unless required for the fix to compile.</rule>
</rules>

<patterns>

<pattern id="navigation-base" rule="@typescript-eslint/no-deprecated" symbol="NavigationBase">
`NavigationBase` is a flat navigation type that predates react-navigation's composite `XyzSceneProps` types. It cannot be replaced with scene-specific types in shared code due to variance constraints in composite navigation props.

**In scene components** (call sites):
Replace `navigation as NavigationBase` casts with `navigation as AppNavigation`:

```typescript
// Before
import type { NavigationBase } from '../../types/routerTypes'
activateWalletTokens(navigation as NavigationBase, wallet, [tokenId])

// After
import type { AppNavigation } from '../../types/routerTypes'
activateWalletTokens(navigation as AppNavigation, wallet, [tokenId])
```

**In shared actions/utilities** (declaration sites):
Replace `NavigationBase` parameter types with `AppNavigation`:

```typescript
// Before
import type { NavigationBase } from '../types/routerTypes'
export function myAction(navigation: NavigationBase): ThunkAction<...> {

// After
import type { AppNavigation } from '../types/routerTypes'
export function myAction(navigation: AppNavigation): ThunkAction<...> {
```

**Why `as` casts are still required**: Composite scene navigation types (e.g. `WalletsTabSceneProps<'transactionList'>['navigation']`) are not structurally assignable to flat navigation types due to `PrivateValueStore` phantom types and contravariance in `dispatch`. The cast is the intended escape hatch.
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
