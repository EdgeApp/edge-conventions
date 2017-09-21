# Edge Coding and Workflow Conventions

## Coding Conventions

* Variable, classes, and types that space usage across more than one file should be named with more than one English word or use a prefix such as `Abc`. Single english words names are hard to uniquely search for.
* Directories and Modules should not have a single file called `index.js` due to the difficulty in finding this file name in a debugging environment. Encorporate the module name in the name of the file. ie. `indexEthereum.js`
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

## Workflow conventions

* All merges into a `master` or `develop` branch should use --no-ff

* Pull request should not be made from branches that were themself branched from a pending pull request