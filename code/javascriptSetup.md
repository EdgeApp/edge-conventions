# [<](README.md) &nbsp; Javascript Project Setup Conventions

* [Testing](#testing)
  * [Jest](#jest)
* [Type Checking](#type-checking)
  * [Flow](#flow)
* [Commit Hooks](#commit-hooks)
  * [Husky](#husky)
* [Formatting](#formatting)
* [Dependencies](#dependencies)
  * [Do](#do)
  * [Don't](#dont)
* [Scripts](#scripts)

&nbsp;

## All Edge javascript projects shall use the following utilities

----

### Testing

#### [Jest][Jest]

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Usage

```javascript
// package.json
"test": "jest"
```

----

[Back to the top](#--javascript-project-setup-conventions)

&nbsp;

### Type Checking

#### [Flow][Flow]

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Usage

```javascript
// package.json
"flow": "flow"
```

----

[Back to the top](#--javascript-project-setup-conventions)

&nbsp;

### Commit Hooks

#### [Husky][Husky]

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Installing

```javascript
yarn add -D husky

```

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Usage

```javascript
// package.json
"pre-push": "yarn test"
```

----

[Back to the top](#--javascript-project-setup-conventions)

&nbsp;

### Formatting

* [eslint-config-standard-kit][eslint-config-standard-kit] - [github](https://github.com/swansontec/eslint-config-standard-kit/)
* [Eslint][Eslint] - [github](https://github.com/eslint/eslint)
* [Prettier][Prettier] - [github](https://github.com/prettier/prettier)
* Lint-staged - [github](https://github.com/okonet/lint-staged)
* Import-sort - [github](https://github.com/renke/import-sort)
* Sort-package-json - [github](https://github.com/keithamus/sort-package-json)

  * Installing

  ```javascript
  yarn add sort-package-json import-sort-cli import-sort-style-module prettier-eslint-cli lint-staged
  ```

  * Usage

  ```javascript
  // package.json
  "scripts": {
    "format": "sort-package-json; import-sort -l --write '*.js' 'src/**/*.js'; prettier-eslint --write '*.js' 'src/**/*.js'",
    "precommit": "lint-staged"
  },
  "prettier": {
    "printWidth": 120
  },
  "lint-staged": {
    "*.js": ["yarn format", "git add"]
  },
  "importSort": {
    ".js, .es": {
      "parser": "babylon",
      "style": "module"
    }
  }
  ```

----

[Back to the top](#--javascript-project-setup-conventions)

&nbsp;

### Dependencies

All dependencies should be defined with their full URLs or NPM package version. [GitHub short-hand URLs](https://docs.npmjs.com/cli/v6/configuring-npm/package-json#github-urls) should not be used due to an [outstanding issue with Yarn not running prepare/prepack](https://github.com/yarnpkg/yarn/issues/5235#issue-289053582) for these types of dependencies.

#### Do

```json
{
  "dependencies": {
    "react": "^17.0.1",
    "edge-currency-accountbased": "git://github.com/EdgeApp/edge-currency-accountbased.git#v0.7.33"
  }
}
```

##### Don't

```json
{
  "dependencies": {
    "edge-currency-accountbased": "EdgeApp/edge-currency-accountbased#v0.7.33"
  }
}
```

----

[Back to the top](#--javascript-project-setup-conventions)

&nbsp;

### Scripts

Each repo should have the following package.json scripts which accomplish the following:

* `build`: If necessary, run rollup, webpack, and flow-copy to populate `lib` folder. Should not run any lint, flow checking, or tests
* `flow`: Run `flow`
* `lint`: Run `standard.js` or equivalent and `flow`
* `test`: Run `lint` and `flow`. Flow should exclude `*.js.flow` files. Lastly run `mocha` or `jest` tests
* `precommit`: Run `build` then `test`
* `prepare`: Run `build`

[Back to the top](#--javascript-project-setup-conventions)

&nbsp;

[eslint-config-standard-kit]: https://www.swansontec.com/eslint-config-standard-kit/
[Eslint]: https://eslint.org/
[Prettier]: https://prettier.io/
[Husky]: https://github.com/typicode/husky
[Jest]:  http://jestjs.io/
[Flow]:  https://flow.org/
