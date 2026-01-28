---
name: review-react
description: Reviews code for React conventions and best practices. Use when reviewing React component files (.tsx).
---

Review the branch/pull request in context for React conventions.

## Context Expected

You will receive:
- Repository name
- Branch name
- List of changed `.tsx` files to review

## How to Review

1. Read the changed component files provided in context
2. Check each rule below against the code
3. Report findings with specific file:line references

---

## Component Exports

Always use the explicit `React.FC<Props>` pattern for functional components:

```typescript
// Correct
export const MyComponent: React.FC<Props> = props => {
  // ...
}

// Incorrect
export const MyComponent = (props: Props) => {
  // ...
}

// Incorrect - missing props parameter even when not used
export const MyComponent: React.FC<Props> = () => {
  // ...
}
```

---

## Return Types for Non-Components

Use `React.ReactElement` as the return type for render functions that are not components:

```typescript
// For render helper functions
const renderItem = (item: Item): React.ReactElement => {
  return <View>{item.name}</View>
}
```

This prevents ESLint from incorrectly inserting `async/await` (since `ReactNode` includes `Promise<...>` but `ReactElement` is fully sync).

---

## Hooks

### useHandler

Prefer `useHandler` over `useCallback` for event handlers and async functions:

```typescript
import { useHandler } from '../../hooks/useHandler'

const handleAction = useHandler(async () => {
  // async handler implementation
})
```

This hook provides better TypeScript inference and handles async functions more gracefully than `useCallback`.

### Custom Hooks

Custom hooks should be placed in `src/hooks/` and follow the `use*` naming convention.

### Combine Related Effects

If two effects update related state, consider combining them:

```typescript
// Incorrect - two separate effects for related state
useEffect(() => {
  setIsKeyboardOpen(value)
}, [value])

useEffect(() => {
  keyboardHeightSv.value = height
}, [height])

// Correct - one effect updates both
useEffect(() => {
  setIsKeyboardOpen(value)
  keyboardHeightSv.value = height
}, [value, height])
```

---

## Selectors

Select only what you need to avoid unnecessary re-renders:

```typescript
// Incorrect - any setting change will re-render
const settings = useSelector(state => state.ui.settings)
const countryCode = settings.countryCode

// Correct - only re-renders when countryCode changes
const countryCode = useSelector(state => state.ui.settings.countryCode)
```

---

## JSX Patterns

### Ternary vs && for Conditionals

Prefer `condition ? element : null` over `condition && element`:

```typescript
// Preferred (lint convention)
{isVisible ? <Component /> : null}

// Avoid
{isVisible && <Component />}
```

### Pass-Through Handlers

Don't create wrapper functions for handlers that just pass through:

```typescript
// Incorrect
const handleCancel = () => onCancel()
return <Input onCancel={handleCancel} />

// Correct - pass directly
return <Input onCancel={onCancel} />
```

---

## Display Logic

Extract complex display logic to helper functions with early returns:

```typescript
// Incorrect - inline conditional logic
const display = selectedCrypto != null && selectedWallet != null
  ? isL2Native
    ? `${code} (${name})`
    : code
  : undefined

// Correct - helper function with early returns
function getSelectedCryptoDisplay(): string | undefined {
  if (selectedCrypto == null) return
  if (selectedWallet == null) return
  if (selectedCryptoCurrencyCode == null) return

  const isL2Native =
    selectedCrypto.tokenId == null &&
    !isAssetNativeToChain(selectedWallet.currencyInfo, undefined)

  return isL2Native
    ? `${selectedCryptoCurrencyCode} (${selectedWallet.currencyInfo.displayName})`
    : selectedCryptoCurrencyCode
}
```

---

## Style Composition

Use React Native's built-in utilities for style composition:

```typescript
// Incorrect - manual array handling
const style = baseStyle != null ? [baseStyle, customStyle] : customStyle

// Correct - use StyleSheet.compose
const style = StyleSheet.compose(baseStyle, customStyle)
```

`StyleSheet.compose` handles null cases automatically.

---

## Event Types

Always type event handler parameters explicitly:

```typescript
// Incorrect - implicit any
const handleLayout = (event) => {
  // ...
}

// Correct - explicit type
const handleLayout = (event: LayoutChangeEvent) => {
  // ...
}
```

---

## Platform-Specific Keyboard Behavior

iOS number-pad keyboards don't support certain `returnKeyType` values. Setting unsupported types causes "Can't find keyplane" warnings:

```typescript
// Incorrect - causes warnings on iOS with number-pad
<TextInput
  keyboardType="number-pad"
  returnKeyType="done"  // iOS number-pad doesn't support this
/>

// Correct - conditionally set returnKeyType
import { Platform } from 'react-native'

<TextInput
  keyboardType="number-pad"
  returnKeyType={Platform.OS === 'ios' ? undefined : 'done'}
/>
```

Test keyboard interactions on both iOS and Android when adding keyboard-related props.

---

## Preserve Props When Replacing Components

When replacing one component with another, ensure all props are carried over:

```typescript
// Original component
<AntDesignIcon
  name="close"
  color={theme.primaryText}
  size={theme.rem(1.25)}
  style={styles.closeIcon}
/>

// Incorrect replacement - missing props
<CloseIcon />  // Lost: color, size, style

// Correct replacement - preserve visual behavior
<CloseIcon
  color={theme.primaryText}
  size={theme.rem(1.25)}
  style={styles.closeIcon}
/>
```

Check the original component's props before replacing. Missing `color`, `size`, or `style` props change the visual appearance.

---

## Maintain Styling When Switching Icon Libraries

Icon replacements must preserve margin, padding, and spacing styles:

```typescript
// Original with styles
<FontAwesomeIcon
  name="chevron-right"
  style={enabled ? styles.arrowIcon : styles.arrowIconDeactivated}
/>

// styles.arrowIcon = { marginHorizontal: theme.rem(0.5) }
// styles.arrowIconDeactivated = { marginRight: 0.25, marginLeft: 0.75 }

// Incorrect - lost margin styles
<ChevronRightIcon color={color} size={size} />

// Correct - wrap with View or pass style prop
<View style={enabled ? styles.arrowIcon : styles.arrowIconDeactivated}>
  <ChevronRightIcon color={color} size={size} />
</View>
```

Icon components from different libraries may not support the same style props.
