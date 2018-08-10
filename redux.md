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

Only Parent Scene components should directly access redux state. All child components should access redux only via selector
functions passed in by the parent scene as props to the child components. Child components connectors should evaluate
the selector and return the result via mapStateToProps. This will prevent re-rendering of the parent component when
only the child component specifically needs access to redux state.

Props of selector based data should allow for either a function or the actual data to be passed as the prop.

#### Why have this structure?

We have a scene, and inside that scene we have a reusable "layout", like a row of a list of something. The layout has some inner leaf components that actually do the work.

- scene
  - layout
    - widget
    - widget
    - widget

#### Easy option

The scene gets all data, and just passes it to its children. Simple & obvious. But this means any change to props needed
by the widgets (child components) will cause the entire parent scene to re-render.

- connect
  - scene
    - layout
      - widget
      - widget
      - widget

#### Efficient option

Each component knows where it data comes from. This means we need an army of very specific leaf components which are not re-usable, since they are specific to the data source of the scene.
It also means the layout is not reusable, since its children are locked to the scene.

- scene
  - layout
    - connect
      - widget
    - connect
      - widget
    - connect
      - widget

#### Wired Components (Hybrid option)

The scene passes selectors to child components as props. The scene knows where in redux the data comes from, like in the easy case. The leaf
components have the actual connections, as in the fast case. They use the selectors passed in, so they are reusable.
This also allows nesting of wired widgets where each layer of widgets does not directly have to know where in redux
its data is coming from.

**Important rule: Wired Components should not directly access `state` but only use it to pass into selectors given through
props**

- scene <- contains selectors
  - layout <- reusable
    - connect <- reusable
      - widget
        - connect <- reusable
          - widget
    - connect
      - widget
    - connect
      - widget

```js
// Not a connected component. Never re-renders.
function Scene() {
  return (
    <Layout
      text={state => state.blah.message}
      image={state => state.foo.avatar}
    />
    <WiredText text={state => state.bar.name} />
    <WiredText text='Hello World' />
  );
}

function Layout (props) {
  <div>
    <WiredImage src={props.image} />
    <WiredText text={props.text} />
  </div>
}

// Image library
const WiredImage = connect(Image, (state, ownProps) => ({
  src: typeof ownProps.src === 'function' ? ownProps.src(state) : ownProps.src
}))

function Image (props) {
  return <img src={props.src} />
}

// Text library
const WiredText = connect(Text, (state, ownProps) => ({
  text: typeof ownProps.text === 'function' ? ownProps.text(state) : ownProps.text
}))
function Text (props) {
  return <p>{props.text}</p>
}
```

### Reducers

### Actions

### Selectors
