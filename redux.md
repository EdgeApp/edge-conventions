# Redux Conventions

### Connectors
* Do not create new objects in connectors

```javascript
const defaults = {
  d: 123,
  e: 456
}

const mapStateToProps = (state: State) => {
  return {
    a: {
      ...defaults,
      ...state.a
    },
    b: state.b,
    c: state.c
  }
}

export const connectedMyComponent = connect(mapStateToProps, mapDispatchToProps)(MyComponent)
```

### Reducers

### Actions

### Selectors
