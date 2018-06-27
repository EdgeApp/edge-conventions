# Repo Conventions

### All Edge javascript repos shall use the following utilities:
* [Jest](#Jest)
* [Husky](#Husky)
* [Eslint](Eslint)
* [Flow](Flow)
* [Import-sort](Import-sort)
* [Prettier](Prettier)

### Jest [(github)](https://github.com/facebook/jest) [(web)](http://jestjs.io/)
  ```
  // package.json
  "test": "jest"
  ```

### Husky [(github)](https://github.com/typicode/husky)
  ```
  // package.json
  "precommit": "npm test"
  ```

### Eslint [(github)](https://github.com/eslint/eslint) [(web)](https://eslint.org/)
  ```
  // package.json
  "lint": "eslint '*.js' 'src/**/*.js'"
  ```

### Flow [(github)](https://github.com/facebook/flow) [(web)](https://flow.org/)
  ```
  // package.json
  "flow": "flow"
  ```

### Import-sort [(github)](https://github.com/renke/import-sort)
```
// package.json
"importSort": {
  ".js, .es": {
    "parser": "babylon",
    "style": "module"
  }
}
```

### Prettier [(github)](https://github.com/prettier/prettier) [(web)](https://prettier.io/)
```
// package.json
"flow": "flow"
```

### Scripts
```
// package.json
"format": "import-sort -l --write '*.js' 'src/**/*.js'; prettier-eslint --write '*.js' 'src/**/*.js'"
```
