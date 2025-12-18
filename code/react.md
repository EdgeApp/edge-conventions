# [<](README.md) &nbsp; React Conventions

* [Component Exports](#component-exports)
* [Hooks](#hooks)
* [Component Patterns](#component-patterns)

&nbsp;

----
&nbsp;

## Component Exports

Components should be exported using the following pattern:

### Preferred Pattern

```typescript
export const ComponentName: React.FC<Props> = props => {
  // component implementation
}
```

[Back to the top](#--react-conventions)

&nbsp;

----

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

Custom hooks should be placed in `src/hooks/` and follow the `use*` naming convention:

```typescript
// src/hooks/useMyHook.ts
export const useMyHook = () => {
  // hook implementation
}
```

[Back to the top](#--react-conventions)

&nbsp;

----

## Component Patterns

### Functional Components

Use functional components with hooks instead of class components:

```typescript
// preferred
export const MyComponent: React.FC<Props> = props => {
  const theme = useTheme()
  const dispatch = useDispatch()
  // component implementation
}

// avoid (unless necessary for legacy code)
export class MyComponent extends React.Component<Props> {
  // class component implementation
}
```

### Error Handling

Use proper error boundaries and avoid throwing errors in render methods. Handle errors gracefully within components.

[Back to the top](#--react-conventions)
