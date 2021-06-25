# [<](README.md) &nbsp; Edge Libraries

- [Motivation](#motivation)
- [Data validation](#data-validation)
- [Data storage](#data-storage)
- [React/Redux](#react-redux)
- [CLI/Dev Tools](#cli-dev-tools)

&nbsp;

## Motivation

These libraries were written by Edge to solve a variety of problems and are used across our repos.\
In most cases, it is required to use this tools when working on our repos.

&nbsp;

## Data validation

- [cleaners][cleaners] - Cleans & validates untrusted data, with TypeScript & Flow support

- [cleaner-configs][configs] - A utility to easily manage strongly-typed JSON configs using cleaners for runtime type-checking

&nbsp;

## Data storage

- [disklet][disklet] - A tiny, composable filesystem API.

- [memlet][memlet] - Memory caching library written on top of the Disklet

- [baselet][baselet] - Simple database built on disklet

&nbsp;

## React/Redux

- [Redux Pixies][Pixies] - The magical Redux side-effects library

- [Redux Keto][Keto] - A tool for building fat reducers

- [Airship][Airship] - The airship floats above your React Native application, providing a place for modals, alerts, menus, toasts, and anything else to appear on top of your normal UI.

- [Yaob (Yet Another Object Bridge)][Yaob] - This library allows software to expose a nice object-oriented API, even if it's trapped behind a messaging interface.

&nbsp;

## CLI/Dev Tools

- [Updot][Updot] - Copy dependencies from repos in the ../ folder to the current repo's node_modules. Useful in a React Native project as npm link is broken.

[Back to the top](#--edge-libraries)

[cleaners]: https://www.npmjs.com/package/cleaners
[configs]: https://www.npmjs.com/package/cleaner-config
[disklet]: https://www.npmjs.com/package/disklet
[memlet]: https://www.npmjs.com/package/memlet
[baselet]: https://www.npmjs.com/package/baselet
[Pixies]: https://www.npmjs.com/package/redux-pixies
[Keto]: https://www.npmjs.com/package/redux-keto
[Airship]: https://www.npmjs.com/package/react-native-airship
[Yaob]: https://www.npmjs.com/package/yaob
[updot]: https://www.npmjs.com/package/updot
