# [<](README.md) &nbsp; Develop to Staging

Merge develop → staging.

## Checklist

### 1. Update edge-react-gui translations

1. Close and delete the existing Crowdin PR, titled "New Crowdin updates", if present: https://github.com/EdgeApp/edge-react-gui/pulls. If not present, there's no translation updates to merge.
2. Go to https://crowdin.com/project/edge/apps/system/github
3. Click EdgeApp / edge-react-gui
4. Click Sync Now
5. Return to https://github.com/EdgeApp/edge-react-gui/pulls
6. Merge new Crowdin PR

> The purpose of closing *and deleting* the existing PR and replacing with a brand new one is to compress all the changes into as few commits as possible. Otherwise, the git graphs blow up and recent work is hard to find.

### 2. Update edge-login-ui-rn translations

1. Close and delete the existing Crowdin PR, titled "New Crowdin updates", if present: https://github.com/EdgeApp/edge-login-ui-rn/pulls. If not present, there's no translation updates to merge.
2. Go to https://crowdin.com/project/edge/apps/system/github
3. Click EdgeApp / edge-login-ui-rn
4. Click Sync Now
5. Return to https://github.com/EdgeApp/edge-login-ui-rn/pulls
6. Merge new Crowdin PR

> The purpose of closing *and deleting* the existing PR and replacing with a brand new one is to compress all the changes into as few commits as possible. Otherwise, the git graphs blow up and recent work is hard to find.

### 3. Update react-native-zcash checkpoints and publish

1. Checkout master and run `yarn update-checkpoints`
2. Commit new checkpoint files
3. Bump version and update changelog
4. Publish
5. Upgrade react-native-zcash in edge-react-gui and commit package.json, yarn.lock, and ios/Podfile.lock changes

### 4. Update react-native-piratechain checkpoints and publish

1. Checkout master and run `yarn update-checkpoints`
2. Commit new checkpoint files
3. Bump version and update changelog
4. Publish
5. Upgrade react-native-piratechain in edge-react-gui and commit package.json, yarn.lock, and ios/Podfile.lock changes

### 5. Update chain-registry package and publish edge-currency-accountbased

1. Checkout master and run `yarn add chain-registry && yarn prepare`
2. Commit changes to package.json and yarn.lock
3. Bump version and update changelog
4. Publish
5. Upgrade edge-currency-accountbased in edge-react-gui and commit package.json, yarn.lock, and ios/Podfile.lock changes

### 6. Update CHANGELOG with version commit

Make a version commit like `vX.Y.Z` for the new version with the following changes:

- Add missing date to previously published staging version in CHANGELOG.md
  - If there are missing dates in other published versions, add the dates
- Bump version in package.json and CHANGELOG.md
  1. Add release section in CHANGELOG (use "staging" instead of date)

### 7. Merge develop to staging

Checkout staging branch and run:

```sh
git merge -X theirs develop
```

Assert that staging and develop are identical:

```sh
git diff develop
```

If there is any diff, some changes from develop were not applied during the merge (e.g. non-conflicting changes that were dropped). Manually apply the missing changes on staging and commit them before continuing.

Check that all checks pass before pushing:

```sh
yarn verify
```

Push staging to publish:

```sh
git push
```
