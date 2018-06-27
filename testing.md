# Testing Conventions

* Jest [(github)](https://github.com/facebook/jest) [(web)](http://jestjs.io/) - test runner
* Detox [(github)](https://github.com/wix/detox) - end to end testing
* Redux Mock Store [(github)](https://github.com/dmitry-zaets/redux-mock-store) - mock redux store

------------------------------------------------------------------------------------------

## Unit Testing

`Units`, usually small, isolated functions, can be tested with [Jest](http://jestjs.io/).

### Synchronous Example
```typescript
// utils.test.js

/* globals describe it expect */

import { mySyncFunction } from './utils.js'

describe('mySyncFunction', () => {
  it('should add 1', () => {
    const someData = 1
    const expected = 2
    const actual = mySyncFunction(someData)

    expect(actual).toEqual(expected)
  })

  it('should throw "My Error Message"', () => {
    const someData = '1'
    const expected = 'My Error Message'

    try {
      mySyncFunction(someData)
    } catch (error) {
      expect(error.message).toEqual(expected)
    }
  })
})
```

### Asynchronous Example
```typescript
// utils.test.js

/* globals describe it expect */

import { myAsyncFunction } from './utils.js'

describe('myAsyncFunction', async () => {
  it('should add 1', () => {
    const someData = 1
    const expected = 2
    const actual = await myAsyncFunction(someData)

    expect(actual).toEqual(expected)
  })

  it('should throw "My Error"', () => {
    const someData = 1
    const expected = 'My Error'

    try {
      await myAsyncFunction(someData)
    } catch (error) {
      expect(error.message).toEqual(expected)
    }
  })
})
```

------------------------------------------------------------------------------------------

### Components (snapshots)
`Components` can be tested with [Jest snapshots](http://jestjs.io/docs/en/snapshot-testing.html).

These tests will fail if, when rendering the `component` given specified props, the result differs from the existing snapshot.

If the change is expected, check the output of the snapshot and confirm that the `component` renders correctly. Then, update the test using

```
yarn test -— -u YourTestName
```

**This will overwrite the existing snapshot with the output of the current test run.**

#### Example
```typescript
// myFeature/myComponent.test.js

/* globals jest describe it expect */

import renderer from 'react-test-renderer'

describe('MyComponent', () => {
  it('should render Some Text', () => {
    const props = {
      someText: 'Some Text',
      onPress: jest.fn
    }
    const actual = renderer.create(<MyComponent {...props} />).toJSON()

    expect(actual).toMatchSnapshot()
  })
})
```

This test will produce a snapshot similar to this.
```typescript
// myFeature/__snapshots__

exports[`renders correctly 1`] = `
<View
  onPress={[Function]}
>
  Some Text
</View>
`;
```


------------------------------------------------------------------------------------------

### Reducers (snapshots)
`Reducers` can be tested with [Jest snapshots](http://jestjs.io/docs/en/snapshot-testing.html).

These tests will fail if, when calling the `reducer` given a specified state and action, the result differs from the existing snapshot.

If the change is expected, check the output of the snapshot and confirm that the `reducer` renders correctly. Then, update the test using

```
yarn test -— -u YourTestName
```

**This will overwrite the existing snapshot with the output of the current test run.**

#### Example
```typescript
// myFeature/myReducer.test.js

/* globals describe it expect */

import { myReducer, initialState, myActions } from './myReducer.js'

describe('myReducer', () => {
  it('should handle success', () => {
    const actual = myReducer(initialState, myActions.success(data))

    expect(actual).toMatchSnapshot()
  })
})
```

This test will produce a snapshot similar to this.
```typescript
// myFeature/__snapshots__
exports[`myReducer should handle success 1`] = `
Object {
  "error": null,
  "isLoading": false,
  "wallets": Array [
    Object {
      "id": 1,
      "name": "My Bitcoin"
    },
    Object {
      "id": 2,
      "name": "My Ethereum"
    }
  ],
  "selected": null
}`;
```
------------------------------------------------------------------------------------------

### Simple Action Creators (snapshots)
`Simple Actions Creators` can be tested with [Jest snapshots](http://jestjs.io/docs/en/snapshot-testing.html).

These tests will fail if, when calling the `simple action creator` with a specified payload, the result differs from the existing snapshot.

If the change is expected, check the output of the snapshot and confirm that the `simple action creator` renders correctly. Then, update the test using

```
yarn test -— -u YourTestName
```

**This will overwrite the existing snapshot with the output of the current test run.**

#### Example
```typescript
// myFeature/myActions.test.js

/* globals describe it expect */

import { myAction } from './myActions.js'

describe('myAction', () => {
  it('should create a MY_ACTION_TYPE action with someData', () => {
    const someData = { id: '123' }
    const actual = myAction(someData)

    expect(actual).toMatchSnapshot()
  })
})
```
This test will produce a snapshot similar to this.
```typescript
// myFeature/__snapshots__
exports[`myAction should create a MY_ACTION_TYPE action with someData 1`] = `
Object {
  id: '123'
}`;
```

------------------------------------------------------------------------------------------

### Complex Action Creators (mock + snapshots)
`Complex Action Creators` can be tested with [Redux Mock Store](https://github.com/dmitry-zaets/redux-mock-store), and [Jest snapshots](http://jestjs.io/docs/en/snapshot-testing.html)

These tests will fail if, when dispatching a `complex action creator`, the `actions record` changes unexpectedly.

> The `actions record` is a list of actions received by a store.

If the change is expected, check the output of the snapshot and confirm that the `action record` renders correctly. Then, update the test using

```
yarn test -— -u YourTestName
```

**This will overwrite the existing snapshot with the output of the current test run.**

#### Example
```typescript
// myFeature/myActions.js

/* globals afterEach describe it expect */

import configureMockStore from 'redux-mock-store'
import thunk from 'redux-thunk'

const middlewares = [ thunk ]
const mockStore = configureMockStore(middlewares)

afterEach(() => {
  mockStore.clearActions()
})

describe('My Feature', () => {
  it('should handle MY_ACTION_TYPE action', async () => {
    const response = 'someData'
    WALLET_API.mockResponseSuccess(response)
    await mockStore.dispatch(myAction(receiveTestData))
    const actual = mockStore.getActions()

    expect(actual).toMatchSnapshot()
  })
})
```

This test will produce a snapshot similar to this.
```typescript
exports[`My Feature should handle MY_ACTION_TYPE 1`] = `
Object {
  "data":
    Object {
      "someData": "someData"
    },
  },
  "type": "MOCK_WALLET_ACTION"
}
`;
```

------------------------------------------------------------------------------------------

## E2E Testing

E2E Testing stands for [End-To-End Testing](https://www.techopedia.com/definition/7035/end-to-end-test). The application can be E2E tested with [Detox](https://github.com/wix/detox).

* Runs a full version of the application (iOS simulator / [android emulator](https://github.com/wix/detox/blob/master/docs/More.AndroidSupportStatus.md) only)
* Uninstalls any existing copies of the application
* Installs a new copy of the application
* Simulates a real user, using taps, swipes, and typing

These tests will fail if, when running the test, any expectation returns false.

Test can fail if:
* A component that is expected to exist, **cannot be found** anywhere on the screen
* A component that is expected to not exist, **can be found** anywhere on the screen
* A component that is expected to be visible, **is not visible** on the screen, possibly covered by the keyboard
* A component that is expected to be not visible, **is visible** on the screen, possibly covered by the keyboard
* A component has an unexpected id
* A component has an unexpected value
* A text component has an unexpected text

E2E tests consists of
* Recognizing components on the screen, by using [Matchers](https://github.com/wix/detox/blob/master/docs/APIRef.Matchers.md)
* Declaring how these components should look on the screen, or what properties they should have, by using [Expectations](https://github.com/wix/detox/blob/master/docs/APIRef.Expect.md)
* Interacting with the components, by using [Actions](https://github.com/wix/detox/blob/master/docs/APIRef.ActionsOnElement.md)

#### Example
```typescript
// e2e/login.test.js

/* globals describe beforeEach device expect it element by */

import { navigateToHome } from './utils.js'

describe('Password Login', () => {
  beforeEach(async () => {
    await device.launchApp({
      permissions: {
        notifications: 'YES',
        camera: 'YES',
        contacts: 'YES'
      }
    })
    await navigateToHome()
  })

  it('should be able to password login', async () => {
    // MATCHERS
    const usernameInput = element(by.type('RCTTextField')).atIndex(1)
    const passwordInput = element(by.type('RCTTextField')).atIndex(0)
    const loginButton = element(by.text('Login'))
    const loginScene = element(by.id('login-scene'))
    const walletListScene = element(by.id('wallet-list-scene'))

    // VERIFY LOGIN SCENE
    await expect(loginScene).toBeVisible()
    await expect(usernameInput).toBeVisible()
    await expect(passwordInput).toBeVisible()
    await expect(loginButton).toExist() // covered by keyboard

    // PASSWORD LOGIN
    await usernameInput.clearText()
    await usernameInput.typeText('JS test 0')
    await passwordInput.typeText('y768Mv4PLFupQjMu')
    await loginButton.tap()

    // VERIFY WALLET LIST SCENE
    await expect(walletListScene).toBeVisible()
  })
})

```
