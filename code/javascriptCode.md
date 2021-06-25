# [<](README.md) &nbsp; Javascript Code Conventions

* [File Names](#file-names)
* [Comments](#comments)
* [Exports](#exports)

&nbsp;

----

## File Names

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

----

[Back to the top](#--javascript-code-conventions)

&nbsp;

## Comments

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

----

[Back to the top](#--javascript-code-conventions)

&nbsp;

## Exports

* Only use named exports

 ```javascript
// incorrect
export default class FullWalletListRow extends Component<OwnProps> {
 // correct
export class FullWalletListRow extends Component<OwnProps> {
```

----

[Back to the top](#--javascript-code-conventions)
