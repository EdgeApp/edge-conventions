# [<](README.md) &nbsp; Server Conventions

* [Server Versions](#server-versions)
* [Client Libraries](#client-libraries)
* [Server Exported Types](#server-exported-types)
* [Client Usage of Server Exported Types](#client-usage-of-server-exported-types)

&nbsp;

Edge uses a micro-services architecture with small code bases each dedicated to a specific purpose (login, file sync, exchange rates, and so forth). Each server lives in its own git repository with a name like "edge-purpose-server". Each server should have `"private": true` in its `package.json` file, since server code does not belong on NPM.

&nbsp;

## Server Versions

Although servers do not live on NPM, we still maintain a `CHANGELOG.md` file and a `package.json` version number for documentation purposes. The version number is in "major.minor" format, with no patch number. The deployment pipeline is responsible for automatically appending a patch version each time it creates & deploys a build, so these patch numbers are not present in the git codebase (similar to the app's build numbers).

* Minor version bumps indicate new features, such as new endpoints.
* Major version bumps indicate deactivated endpoints.

Servers should never implement breaking changes. If a change cannot be backwards-compatible, it should exist as a new endpoint. Old endpoints should be deprecated & eventually deactivated after some period of time. Deactivated endpoints should not be deleted, but should instead return HTTP status code 410, "Gone", or some other similar error.

[Back to the top](#--server-conventions)

&nbsp;

## Client Libraries

Each Edge server should come with a matching client library, typically named "edge-purpose-client". This library should implement all the logic needed to communicate with the server, including knowledge of the server's endpoints, query parameters, required HTTP headers, request & reply formats, and any algorithms needed to make use of the server's data.

For instance, the client library "edge-sync-client" would include the logic needed to maintain a repository on disk, identifying out-of-date files and synchronizing changes with the server. The client library "edge-info-client" might know how to fetch lists of resources from the info server, as well as logic for performing client-side load balancing using these resource lists.

These client libraries are versioned independently from the server they communicate with, since they can implement bug fixes and add features without necessarily requiring server changes (and vice-versa). Client libraries should be versioned using [Semantic Versioning](https://semver.org/).

Servers are encouraged to share code with their client libraries, such as type definitions, cleaners, constant definitions, and so forth. Putting the shared code in the client library is the most convenient option, since the client would be published to NPM for easy consumption by the server. However it is also possible to share code the other way around (from the server, as below).

[Back to the top](#--server-conventions)

&nbsp;

## Server Exported Types

Although each Edge server should provide its own client library, it is also possible to expose a collection of cleaner functions from the server repository itself. Since server code should not be published to NPM, clients wishing to take advantage of this information should import the server via git URL, like `"edge-info-server": "git://github.com/EdgeApp/edge-info-server.git#v1.0"`

Inside the server repository, the `package.json` fields `main` and `types` should point to the exported cleaners, as shown here:

```ts
// types.ts
import { asArray, asNumber, asObject, asString } from 'cleaners'

// Example of an API request body
export type ApiGetRequest = ReturnType<typeof asApiGetRequest>
export const asApiGetRequest = asObject({
  currencyCode: asString
})

// Example of an API response object
export type ApiGetResponse = ReturnType<typeof asApiGetResponse>
export const asApiGetResponse = asObject({
  transactions: asArray(asObject({
    txid: asString,
    amount: asString,
    //...
  }))
})

// ...
```

Including the following declarations in the package.json manifest file will export the TypeScript types and cleaners from the server:

```json
{
  "name": "my-server",
  "version": "1.0.1",
  ...
  "main": "lib/types.js",
  "types": "lib/types.d.ts",
  "files": [
    "lib/*"
  ],
  "scripts": {
    ...
    "build.lib": "sucrase -q -t typescript,imports,jsx -d ./lib ./src",
    "build.types": "tsc && cpr lib/src lib/ && rimraf lib/src",
    "clean": "rimraf lib",
    "prepare": "npm-run-all clean -p build.*",
    ...
  },
  ...
  "dependencies": {
    ...
    "cleaners": "^0.3.2",
    ...
  },
  "devDependencies": {
    ...
    "cpr": "^3.0.1",
    "npm-run-all": "^4.1.5",
    "sucrase": "^3.12.1",
    "typescript": "^4.1.3"
    ...
  }
}
```

Here's a breakdown describing each dependency and configuration:

* `"main"` and `"types"` are set to the location for the exported types build output (cleaners from the .js file and type declarations from the .d.ts file)
* `"files"` is set to include all files in the `lib/` dir (our output build directory). This means that tarball artifacts can be created using `npm pack` or `yarn pack` if ever necessary.
* Our scripts include:
  * `"prepare"` our main build script which first cleans the build output dir (`lib/`) and then runs all our separate build steps in parallel.
  * `"build.lib"` will build the JS files to `lib/` from the TS files in `src/` using `sucrase` and our typescript configuration (`tsconfig.json`).
  * `"build.types"` will build the type declaration files (`d.ts` files) to `lib/src` from the TS files in `src/` and then move those files to `lib/`.
  * `"clean"` is our cleanup script which removes the `lib/` build directory.
* The following dependencies are necessary for this setup:
  * `cleaners`: Used for runtime type definitions for runtime type validation.
  * `cpr`: Necessary for moving directories in our build scripts.
  * `npm-run-all`: Necessary for running our scripts in parallel
  * `sucrase`: Necessary for running/building typescript (as a faster alternative to using tsc for JS output).
  * `typescript`: Necessary for building type definition files and for development.

[Back to the top](#--server-conventions)

&nbsp;

## Client Usage of Server Exported Types

A client may use the exported types from a server by including it as a dependency using the GitHub repo URL in its `package.json` file:

```json
{
  ...
  "dependencies": {
    "my-server": "git://github.com/EdgeApp/my-server.git#v1.0"
  }
  ...
}
```

Notice the git tag `v1.0` is included in the URL to point to a specific server version for the dependency.

The client can then import the types:

```ts
import { asApiGetRequest, asApiGetResponse } from 'my-server'

// ... Use cleaners to sanitize and validate IO to the server
```

Because server versions track the API changes of the HTTP interface and _not_ the versioning of any exported types, there are no guarantees that types wont have breaking changes from one server version to another. This is one of the caveats to exporting types from the server, and why it is recommended to define and export types on a complementary client-side library for the server (see 'Client Libraries' above).

[Back to the top](#--server-conventions)
