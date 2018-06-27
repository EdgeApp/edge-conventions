# Naming Conventions

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
