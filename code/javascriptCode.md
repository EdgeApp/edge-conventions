# [<](README.md) &nbsp; JavaScript Code Conventions

* [Comments](#comments)
* [Exports](#exports)

&nbsp;

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
