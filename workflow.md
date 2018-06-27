# Workflow Conventions

* Use `no-ff` when merging into 'master' or 'develop'

```bash
# incorrect
> git checkout develop
> git merge new-feature/my-new-feature

# correct
> git checkout develop
> git merge --no-ff new-feature/my-new-feature
```

* If branched from a branch other than `develop` or `master`, wait for any dependent branches to be merged before requesting a pull request
* Before making any changes to a javascript file, enable Flow and resolve any errors in a stand-alone commit
* Install `husky` as a devDependency in all repos
* Only commit debug logging if it includes any of the following types of information:

    - Errors
    - Change in network status (server connect/disconnect)
    - Airbitz Core API calls
    - User interactions
    - Currency Plugin API calls
    - Network events (incoming money, git sync with new data)

```javascript
// incorrect
console.log('tx.amountSatoshi', tx.amoutSatoshi)
console.log('this.props.wallet', this.props.wallet)

// correct
console.log('Error: Insufficient Funds')
console.log('Logout Requested')
console.log('Network Disconnected')
```

* Each repo should have the following package.json scripts which accomplish the following

    - `build`: If necessary, run rollup, webpack, and flow-copy to populate `lib` folder. Should not run any lint, flow checking, or tests
    - `flow`: Run `flow`
    - `lint`: Run `standard.js` or equivalent and `flow`
    - `test`: Run `lint` and `flow`. Flow should exclude `*.js.flow` files. Lastly run `mocha` or `jest` tests
    - `precommit`: Run `build` then `test`
    - `prepare`: Run `build`
