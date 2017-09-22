# Edge Coding and Workflow Conventions

## Coding Conventions

* Use two or more words or the prefix `Abc` when naming exported variables, exported classes, and exported types

```javascript
// incorrect
export class Transaction {...}
export type Data = {...}

// correct
export class AbcTransaction {...}
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
class ABCAccount = {...}
const GUIWallet = {...}
const enableOTP = () => {...}

// correct
class AbcAccount = ...
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
const tx: AbcTransaction = getTransaction()
const accountObject: AbcAccount = getAccount()

// correct
const abcTransaction: AbcTransaction = getTransaction()
const abcAccount: AbcAccount = getAccount()
```

* Prefer naming arrays of objects the same as its globally defined type, when using a globally defined type

```javascript
// incorrect
const txs: Array<AbcTransaction> = getTransactions()
const wallets: Array<AbcWallets> = getWallets()

// correct
const abcTransactions: Array<AbcTransaction> = getTransactions()
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

* If branched from a branch other than develop, wait for any dependent branches to be merged before requesting a pull request

* Before making any changes to a javascript file, enable Flow and resolve any errors in a stand-alone commit

* Lint each repo with a ruleset at least as strict as `standard.js`

* In each repo, include a test script (`npm test`) that, at minimum, lints the repo

* In each repo, include a precommit script (`npm precommit`), via Husky, that includes `npm build` (if it exists) and `npm test`

* Only commit debug logging if it includes any of the following types of information:
    1. Errors
    2. Change in network status (server connect/disconnect)
    3. Airbitz Core API calls
    4. User interactions
    5. Currency Plugin API calls
    6. Network events (incoming money, git sync with new data)

```javascript
// incorrect
console.log('tx.amountSatoshi', tx.amoutSatoshi)
console.log('this.props.wallet', this.props.wallet)

// correct
console.log('Error: Insufficient Funds')
console.log('Logout Requested')
console.log('Network Disconnected')
```
