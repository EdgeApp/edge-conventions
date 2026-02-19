---
name: review-servers
description: Reviews server repositories for dependency management and package structure. Use when reviewing *-server repositories.
---

Review the branch/pull request in context for server repository conventions.

## Scope

This agent only applies to server-based repositories, identified by either:
- Repository name ending in `-server` (e.g., `edge-login-server`, `edge-info-server`)
- Presence of a `pm2.json` file at the repository root

## Context Expected

You will receive:
- Repository name
- Branch name
- List of changed files to review

## How to Review

1. Verify the repository is a server (name ends in `-server` or has `pm2.json` at root)
2. If `package.json` is changed, check dependency placement
3. Verify dependencies vs devDependencies follow conventions
4. Report findings with specific file:line references

---

## Dependencies Belong in devDependencies

Server packages should place all dependencies in `devDependencies`, not `dependencies`. The only exception is cleaner packages, which belong in `dependencies` since they may be exported as types to an NPM package.

```json
// Incorrect - runtime dependencies in dependencies
{
  "dependencies": {
    "express": "^4.18.2",
    "nano": "^10.1.2",
    "node-fetch": "^3.3.0"
  },
  "devDependencies": {
    "typescript": "^5.0.0"
  }
}

// Correct - only cleaners in dependencies, everything else in devDependencies
{
  "dependencies": {
    "cleaners": "^0.3.16"
  },
  "devDependencies": {
    "express": "^4.18.2",
    "nano": "^10.1.2",
    "node-fetch": "^3.3.0",
    "typescript": "^5.0.0"
  }
}
```

**Why:** Server repositories may export TypeScript types that use cleaner types. Consumers of these types need `cleaners` available. All other dependencies are only needed at build/runtime on the server itself and should not pollute the dependency tree of downstream packages.

---

## Separate Config Files for Server and Client

Server and client configuration must be kept in separate files with standard naming:

- `serverConfig.json` — Server-side configuration
- `clientConfig.json` — Client-side configuration (served to browser/app)

Both config files must be validated using cleaners. The server config should use the `cleaner-config` library for loading and validation:

```typescript
// Incorrect - single config file for both, no validation
import config from './config.json'

const serverPort = config.port
const clientApiUrl = config.clientApiUrl  // Mixing concerns

// Correct - separate files with cleaner validation
import { makeConfig } from 'cleaner-config'
import { asObject, asNumber, asString } from 'cleaners'

// Server config (config.json)
const asServerConfig = asObject({
  port: asNumber,
  dbUrl: asString,
  secretKey: asString
})
const serverConfig = makeConfig(asServerConfig, 'serverConfig.json')

// Client config (clientConfig.json)
const asClientConfig = asObject({
  apiUrl: asString,
  appName: asString
})
const clientConfig = makeConfig(asClientConfig, 'clientConfig.json')
```

**Why:** Separating configs prevents accidentally exposing server secrets to clients. Using cleaners ensures config files match expected schemas and fail fast on misconfiguration.

---

## Use PM2 for Process Management

Server processes must be launched using PM2 with a `pm2.json` configuration file at the repository root. Do not use raw `node` commands or other process managers.

### Standard Entry Point Structure

Servers typically have two entry points:

| Purpose | Source File | Built File |
|---------|-------------|------------|
| HTTP API server | `src/server/indexApi.ts` | `lib/server/indexApi.js` |
| Background engines | `src/server/indexEngine.ts` | `lib/server/indexEngine.js` |

The API process handles incoming HTTP requests and can run in cluster mode. The engine process runs background tasks, scheduled jobs, and long-running services.

### PM2 Configuration

```json
// pm2.json
{
  "apps": [
    {
      "name": "exampleServer",
      "script": "lib/server/indexApi.js",
      "instances": "max",
      "exec_mode": "cluster",
      "error_file": "/var/log/pm2/exampleServer.error.log",
      "out_file": "/var/log/pm2/exampleServer.out.log"
    },
    {
      "name": "exampleEngines",
      "script": "lib/server/indexEngine.js",
      "error_file": "/var/log/pm2/exampleEngines.error.log",
      "out_file": "/var/log/pm2/exampleEngines.out.log"
    }
  ]
}
```

```bash
# Incorrect - running node directly
node lib/server/indexApi.js

# Incorrect - using npm start without PM2
npm start

# Correct - using PM2 with config file
pm2 start pm2.json
```

**Why:** PM2 provides process monitoring, automatic restarts on crash, log management, and cluster mode support. The `pm2.json` file ensures consistent deployment configuration across environments. Separating API and engine processes allows the API to scale horizontally in cluster mode while engines run as a single instance to avoid duplicate background work.

### Build Scripts for Server and Client

When a server repository includes both a backend server and a frontend client (web UI), the `build` script must build both. Use `npm-run-all` to run build scripts in parallel:

```json
// Incorrect - only builds server
{
  "scripts": {
    "build.web": "webpack --mode production",
    "build.server": "tsc -p tsconfig.server.json",
    "build": "yarn build.server"
  }
}

// Correct - builds both server and client in parallel
{
  "scripts": {
    "build.web": "webpack --mode production",
    "build.server": "tsc -p tsconfig.server.json",
    "build": "npm-run-all -p build.*"
  }
}
```

**Why:** The `build` script is the canonical entry point for producing deployment artifacts. If only the server is built, the client assets will be missing in production. Using `npm-run-all -p build.*` runs all `build.*` scripts in parallel for faster builds and ensures nothing is forgotten.
