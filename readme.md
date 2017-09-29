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
* All repos should `husky` installed as a devDependency
* Debug logging can only be committed to the repo and on by default for the following types of information

    - Errors
    - Change in network status (server connect/disconnect)
    - Airbitz Core API calls
    - User GUI actions
    - Currency Plugin API calls
    - Network events (incoming money, git sync with new data)
    
* Each repo should have the following package.json scripts which accomplish the following

    - `build`: If necessary, run rollup, webpack, and flow-copy to populate `lib` folder. Should not run any lint, flow checking, or tests
    - `flow`: Run `flow`
    - `lint`: Run `standard.js` or equivalent and `flow`
    - `test`: Run `lint` and `flow`. Flow should exclude `*.js.flow` files. Lastly run `mocha` or `jest` tests
    - `precommit`: Run `build` then `test`
    - `prepare`: Run `build`
