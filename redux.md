# Redux Conventions

### Async Error Handling

```javascript
import { InsufficientFundsError } from ‘edge-core-js’

WALLET_API.someCall(edgeWallet, someInputs).then(handleSuccess, handleError)

const handleSuccess = (someData) => {...do stuff with data}

const handleError = (error: Error) => {
  if (error instanceof InsufficientFundsError) {
    return dispatch(displayInsufficientFundsAlert())
  }
  dispatch(unknownError(error)) // Handles all other error types
}
```

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

### Parent Scene vs Child Components

Only Parent components should directly access redux state. All child components should access redux only via selector functions passed in by the parent scene as props to the child components. Child components should then simply assign a local state variable with the return value of the selector. This will prevent re-rendering of the parent component when only the child component specifically needs access to redux state.

ie.

In `MyParentComponentSceneConnector.js`
```javascript
import { connect } from 'react-redux'

import type { Dispatch, State } from '../../modules/ReduxTypes'
import { MyParentComponentScene } from './MyParentComponentScene.js'

const getSomeReduxStateSelector = (state: State) => state.someReduxState
const getMoreReduxStateSelector = (state: State) => state.moreReduxState

export const mapStateToProps = (state: State) => ({
  getSomeReduxState: getSomeReduxStateSelector,
  getMoreReduxState: getMoreReduxStateSelector
})

export const mapDispatchToProps = (dispatch: Dispatch) => ({
})

export const MyParentComponentScene = connect(mapStateToProps, mapDispatchToProps)(MyParentComponentScene)

```

In `MyParentComponentScene.js`
```javascript
export class MyParentComponentScene extends Component<Props, State> {
  render () {
    <MyChildComponent
      stateSelector1=props.getSomeReduxState
      stateSelector2=props.getMoreReduxState
    >
  }
}
```


In `MyChildComponent.js`
```javascript
export type MyChildComponentStateProps = {
  state1: string,
  state2: boolean
}

type Props = MyChildComponentStateProps

export class MyChildComponentInner extends Component<Props, State> {
  render () {
    // Use props.state1 and props.state2 in render
  }
}

export const mapStateToProps = (state: State, ownProps: any) => ({
  state1: ownProps.stateSelector1(state),
  state2: ownProps.stateSelector1(state)
})

export const MyChildComponent = connect(mapStateToProps, mapDispatchToProps)
```
### Reducers

### Actions

### Selectors
