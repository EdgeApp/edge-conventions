# Edge Coding and Workflow Conventions

## Coding Conventions

* Use two or more words or the prefix `Edge` when naming exported variables, exported classes, and exported types

```javascript
// incorrect
export class Transaction {...}
export type Data = {...}

// correct
export class EdgeTransaction {...}
export type ExchangeRateData = {...}
```

* Postfix the names of index files with the name of its parent directory

```javascript
// incorrect
src/
  components/
    MyComponent/
      index.js // <--
      MyComponent.js
      styles.js

// correct
src/
  components/
    MyComponent/
      indexMyComponent.js // <--
      MyComponent.js
      styles.js
```

* Use [Pascal Case](https://en.wikipedia.org/wiki/PascalCase) when naming classes, interfaces, and types

```javascript
// incorrect
type mySpecialType = {...}
type My_Special_Type = {...}
type MY_SPECIAL_TYPE = {...}

// correct
type MySpecialType = {...}
```

* Use camel case when naming variables (other than constants), functions, and methods

```javascript
// incorrect
const MySpecialVar = {...}
const My_Special_Var = {...}
const MY_SPECIAL_VAR = {...}

// correct
const mySpecialVar = {...}
class MySpecialClass {
  mySpecialMethod () {...} // <--
}
```

* Use camel case when using acronyms in variables, classes, or type names

```javascript
// incorrect
class EDGEAccount = {...}
const GUIWallet = {...}
const enableOTP = () => {...}

// correct
class EdgeAccount = ...
const GuiWallet = ...
const enableOtp = () => ...
```

* Use `TODO + initials` comments to label any code as not production ready

```javascript
// incorrect
const denomination = {
  currencyCode: 'USD' // Yikes!! this should definitely be changed
}

// correct
const denomination = {
  currencyCode: 'USD' // Todo: Replace hard coded currencies with library -paulvp
}
```

* Break more than double nested array dereferences into multiple lines

```javascript
// incorrect

// correct

```
* Break more than double nested or function calls into multiple lines

```javascript
// incorrect

// correct

```

* Prefer naming objects the same as its globally defined type, when using a globally defined type

```javascript
// incorrect
const tx: EdgeTransaction = getTransaction()
const accountObject: EdgeAccount = getAccount()

// correct
const edgeTransaction: EdgeTransaction = getTransaction()
const edgeAccount: EdgeAccount = getAccount()
```

* Prefer naming arrays of objects the same as its globally defined type, when using a globally defined type

```javascript
// incorrect
const txs: Array<EdgeTransaction> = getTransactions()
const wallets: Array<EdgeWallets> = getWallets()

// correct
const edgeTransactions: Array<EdgeTransaction> = getTransactions()
```

## React Conventions

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

## Workflow conventions

* Use `no-ff` when merging into 'master' or 'develop'

```bash
# incorrect
> git checkout develop
> git merge new-feature/my-new-feature

# correct
> git checkout develop
> git merge --no-ff new-feature/my-new-feature
```

* If branched from a branch other than `develop` or `master`, wait for any dependent branches to be merged before requesting a pull request
* Before making any changes to a javascript file, enable Flow and resolve any errors in a stand-alone commit
* Install `husky` as a devDependency in all repos
* Only commit debug logging if it includes any of the following types of information:

    - Errors
    - Change in network status (server connect/disconnect)
    - Airbitz Core API calls
    - User interactions
    - Currency Plugin API calls
    - Network events (incoming money, git sync with new data)

```javascript
// incorrect
console.log('tx.amountSatoshi', tx.amoutSatoshi)
console.log('this.props.wallet', this.props.wallet)

// correct
console.log('Error: Insufficient Funds')
console.log('Logout Requested')
console.log('Network Disconnected')
```

* Each repo should have the following package.json scripts which accomplish the following

    - `build`: If necessary, run rollup, webpack, and flow-copy to populate `lib` folder. Should not run any lint, flow checking, or tests
    - `flow`: Run `flow`
    - `lint`: Run `standard.js` or equivalent and `flow`
    - `test`: Run `lint` and `flow`. Flow should exclude `*.js.flow` files. Lastly run `mocha` or `jest` tests
    - `precommit`: Run `build` then `test`
    - `prepare`: Run `build`
