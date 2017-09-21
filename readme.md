# Edge Coding and Workflow Conventions

## Coding Conventions

* Variable, classes, and types that space usage across more than one file should be named with more than one English word or use a prefix such as `Abc`. Single english words names are hard to uniquely search for.
* Directories and Modules should not have a single file called `index.js` due to the difficulty in finding this file name in a debugging environment. Encorporate the module name in the name of the file. ie. `indexEthereum.js`
* Class, interface, and type names should be camel case and begin with an upper case letter
* Variable, function, and method names should be camel case but begin with a lower case letter
* Acronyms in variable, class, or type names should be camel cased. ie. `AbcAccount`, `GuiWallet`, `enableOtp`. Not `ABCAccount`
* Any code that needs to be fixed prior to the next production release should be commented and suffixed with developers name. ie.

    `// Todo: Remove hard coded currencies and replace with module -paulvp`

* More than double nested array dereferences or function calls should be broken up into multiple lines
* Allocations of an object with a globally defined type should be named after that type as much as possible. ie.

    `const abcTransaction: ABCTransaction = getTransaction()`

* Allocations of an array of objects with a globally defined type should be named after that type as much as possible. ie.

    `const abcTransactions: Array<ABCTransaction> = getTransactions()`

## Workflow conventions

* All merges into a `master` or `develop` branch should use --no-ff
* Pull requests should not be made from branches that were themself branched from a pending pull request
* Edits to any files that do not yet have Flow enabled should first enable Flow via a separate commit
* All repos should be at minimum `standard.js` linted
* All repos should have an `npm test` that at least includes`standard.js` linting
* All repos should have an `npm precommit`, via Husky, that includes `npm build` (if exists) and `npm test`
* Debug logging can only be committed to the repo and on by default for the following types of information

    1. Errors
    2. Change in network status (server connect/disconnect)
    3. Airbitz Core API calls
    4. User GUI actions
    5. Currency Plugin API calls
    6. Network events (incoming money, git sync with new data)
