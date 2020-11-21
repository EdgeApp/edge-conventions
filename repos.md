# Repo Conventions

### All Edge javascript repos shall use the following utilities:
----
### Testing
#### Jest [(github)](https://github.com/facebook/jest) [(web)](http://jestjs.io/)
  ##### Usage
  ```javascript
  // package.json
  "test": "jest"
  ```
----
### Type Checking
#### Flow [(github)](https://github.com/facebook/flow) [(web)](https://flow.org/)
  ##### Usage
  ```javascript
  // package.json
  "flow": "flow"
  ```
----
### Commit Hooks
#### Husky [(github)](https://github.com/typicode/husky)
  #### Installing
  ```javascript
  yarn add -D husky
  ```
  ##### Usage
  ```javascript
  // package.json
  "pre-push": "yarn test"
  ```
----
### Formatting
* Eslint [(github)](https://github.com/eslint/eslint) [(web)](https://eslint.org/)
* Prettier [(github)](https://github.com/prettier/prettier) [(web)](https://prettier.io/)
* Lint-staged [(github)](https://github.com/okonet/lint-staged)
* Import-sort [(github)](https://github.com/renke/import-sort)
* Sort-package-json [(github)](https://github.com/keithamus/sort-package-json)
  #### Installing
  ```javascript
  yarn add sort-package-json import-sort-cli import-sort-style-module prettier-eslint-cli lint-staged
  ```
  ##### Usage
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
## Dependencies

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

#### Don't
```json
{
  "dependencies": {
    "edge-currency-accountbased": "EdgeApp/edge-currency-accountbased#v0.7.33"
  }
}
```
----
## Scripts

Each repo should have the following package.json scripts which accomplish the following:

- `build`: If necessary, run rollup, webpack, and flow-copy to populate `lib` folder. Should not run any lint, flow checking, or tests
- `flow`: Run `flow`
- `lint`: Run `standard.js` or equivalent and `flow`
- `test`: Run `lint` and `flow`. Flow should exclude `*.js.flow` files. Lastly run `mocha` or `jest` tests
- `precommit`: Run `build` then `test`
- `prepare`: Run `build`
