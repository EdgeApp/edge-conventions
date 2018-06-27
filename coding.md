# Coding Conventions

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
