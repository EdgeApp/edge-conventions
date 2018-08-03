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

Only Parent components should be connected to redux via the `Connect()` function with a mapStateToProps and mapDispathToProps routine. All child components should NOT be directly connected to redux. Instead, parent components should pass in selector functions as props to the child components. Child components should then be defined as `PureComponent` and simply assign a local state variable with the return value of the selector. This will prevent re-rendering of the parent component when only the child component specifically needs access to redux state.

ie.

In `MyParentComponentSceneConnector.js`
```
import { connect } from 'react-redux'

import type { Dispatch, State } from '../../modules/ReduxTypes'
import { MyParentComponentScene } from './MyParentComponentScene.js'

function getSomeReduxStateSelector (state: State) = () => state.someReduxState
function getMoreReduxStateSelector (state: State) = () => state.moreReduxState

export const mapStateToProps = (state: State) => ({
  getSomeReduxState: getSomeReduxStateSelector(state),
  getMoreReduxState: getMoreReduxStateSelector(state)
})

export const mapDispatchToProps = (dispatch: Dispatch) => ({
})

const MyParentComponentScene = connect(mapStateToProps, mapDispatchToProps)(MyParentComponentScene)
export MyParentComponentSceneConnected

```

In `MyParentComponentScene.js`
```
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
```
type State = {
  state1: boolean,
  state2: string
}

export class MyChildComponent extends PureComponent<Props, State> {
  constructor (props: Props) {
    this.state = {
      state1: false,
      state2: ''
    }
  }

  getDerivedStateFromProps(nextProps: Props, prevState: State) {
    const newState = {
      state1: nextProps.stateSelector1()
      state2: nextProps.stateSelector2()
    }
    return newState
  } 
  
  render () {
    // Use state1 and state2 in render
  }
}
```
### Reducers

### Actions

### Selectors
