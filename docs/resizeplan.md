# resizeCluster.ts Specification

A script to resize all nodes in a CouchDB cluster with zero data loss.

## Usage

```bash
yarn resizeCluster [-dryRun]
```

### Command Line Arguments

| Flag | Required | Description |
|------|----------|-------------|
| `-dryRun` | No | Perform all queries but skip shutdown/resize operations |

### Configuration File

All other settings are stored in `resizeCluster.json` in the edge-devops root directory. This file is git-ignored to prevent accidental commits of sensitive entry names.

**Auto-creation:** If `resizeCluster.json` does not exist, the script creates a template file and exits immediately. This happens in both normal and dry-run mode.

```json
{
  "couchUser": "admin",
  "couchPwEntry": "Bitwarden Entry Name for CouchDB",
  "sudoPwEntry": "Bitwarden Entry Name for Sudo",
  "slug": "s-4vcpu-8gb",
  "nodes": [
    "node1.example.com",
    "node2.example.com",
    "node3.example.com"
  ]
}
```

| Field | Description |
|-------|-------------|
| `couchUser` | CouchDB admin username |
| `couchPwEntry` | Bitwarden entry name for CouchDB password |
| `sudoPwEntry` | Bitwarden entry name for server sudo password |
| `slug` | DigitalOcean droplet size slug |
| `nodes` | Array of DNS names for cluster nodes |

## Execution Flow

### 1. Initialization

1. Load `resizeCluster.json` via `makeConfig` from `cleaner-config`:
   - If missing: `makeConfig` creates template file with defaults
   - Check if config has placeholder values → print message and **exit immediately**
   - If valid: continue with validated config
2. Parse `-dryRun` flag from command line
3. Unlock Bitwarden session (prompts for fingerprint)
4. Retrieve passwords from Bitwarden:
   ```bash
   bw unlock  # If needed
   export BW_SESSION="..."
   bw get password "entry name"
   ```

### 2. Pre-flight Checks

1. Query each droplet via DigitalOcean API to get current size
2. Skip any nodes already at the target slug size (enables partial resume)
3. Verify CouchDB cluster is fully synchronized:
   - `GET /_membership` — confirm `all_nodes` equals `cluster_nodes` (all nodes connected)
   - `GET /_node/{node}/_system` on each node — check `internal_replication_jobs` is 0
4. If not synchronized, retry every 5 seconds for up to 5 minutes, then abort

### 3. Per-Node Resize Loop

For each node that needs resizing:

1. **Stop CouchDB**
   ```bash
   ssh -t $HOST "sudo -S systemctl stop couchdb" <<< "$SUDO_PW"
   ```

2. **Shutdown server**
   ```bash
   ssh -t $HOST "sudo -S shutdown -h now" <<< "$SUDO_PW"
   ```

3. **Resize droplet** via `yarn resize <node> <slug>`
   - Existing script handles: shutdown verification, resize API call, power on

4. **Wait for node recovery**
   - Poll until SSH is accessible
   - Poll `GET /_up` until it returns `{"status": "ok"}`
   - CouchDB auto-starts via systemd

5. **Wait for cluster sync**
   - Check `/_membership` — node rejoins `cluster_nodes`
   - Check `/_node/_local/_system` — `internal_replication_jobs` returns to 0
   - Poll every 5 seconds, timeout after 5 minutes
   - Only proceed to next node once cluster is healthy

6. **Log progress** — show current step, completed nodes, and remaining nodes

### 4. Completion

- Print summary of all resized nodes
- Exit with status 0 on success

## Error Handling

If any operation fails:

1. Print summary of completed operations
2. Print which node and step failed
3. Exit with non-zero status

The skip-already-resized logic allows re-running the script to resume after fixing issues.

## Implementation Notes

### Config File with cleaner-config

Use the `cleaner-config` library which handles auto-creation and validation automatically.

```typescript
import { makeConfig } from 'cleaner-config'
import { asArray, asObject, asOptional, asString } from 'cleaners'

// Cleaner with default values for auto-generated template
const asResizeClusterConfig = asObject({
  couchUser: asOptional(asString, 'admin'),
  couchPwEntry: asOptional(asString, 'Bitwarden Entry Name for CouchDB'),
  sudoPwEntry: asOptional(asString, 'Bitwarden Entry Name for Sudo'),
  slug: asOptional(asString, 's-4vcpu-8gb'),
  nodes: asOptional(asArray(asString), [
    'node1.example.com',
    'node2.example.com',
    'node3.example.com'
  ])
})

// makeConfig auto-creates file with defaults if missing, then loads and validates
const config = makeConfig(asResizeClusterConfig, 'resizeCluster.json')
```

The `makeConfig` function from `cleaner-config`:
- Creates `resizeCluster.json` with default values if it doesn't exist
- Loads and validates the config using the cleaner
- Returns the typed config object

```typescript
// Exit if config still has placeholder values
if (config.couchPwEntry.includes('Bitwarden Entry Name')) {
  console.log('Edit resizeCluster.json with your settings and run again.')
  process.exit(0)
}
```

### Cleaners Throughout

Use cleaners for all external data validation:

```typescript
// API response cleaners
const asMembershipResponse = asObject({
  all_nodes: asArray(asString),
  cluster_nodes: asArray(asString)
})

const asSystemResponse = asObject({
  internal_replication_jobs: asNumber
})

const asUpResponse = asObject({
  status: asString
})
```

### Refactor `resizeDroplet.ts`

Extract core functions into a shared library so `resizeCluster.ts` can import:

- `getDropletByName()`
- `shutdownDroplet()`
- `resizeDroplet()`
- `powerOnDroplet()`
- `checkActionStatus()`

### CouchDB Sync Check

For **internal cluster synchronization** (shard replicas within the cluster), check the `internal_replication_jobs` metric on each node. This is different from inter-cluster replication which uses `_replicator`.

**Documentation References:**
- [/_membership](https://docs.couchdb.org/en/stable/api/server/common.html#membership) — cluster node status
- [/_node/{node}/_system](https://docs.couchdb.org/en/stable/api/server/common.html#node-node-name-system) — node system info including `internal_replication_jobs`
- [Shard Management - Monitor internal replication](https://docs.couchdb.org/en/stable/cluster/sharding.html#monitor-internal-replication-to-ensure-up-to-date-shard-s)

```typescript
import { asArray, asNumber, asObject, asString } from 'cleaners'

const asMembershipResponse = asObject({
  all_nodes: asArray(asString),
  cluster_nodes: asArray(asString)
})

const asSystemResponse = asObject({
  internal_replication_jobs: asNumber
})

async function isClusterSynced(hosts: string[], user: string, password: string): Promise<boolean> {
  const auth = { headers: { Authorization: `Basic ${btoa(`${user}:${password}`)}` } }

  // Check all nodes are connected via any host
  const membershipRaw = await fetch(`https://${hosts[0]}:5984/_membership`, auth).then(r => r.json())
  const membership = asMembershipResponse(membershipRaw)
  if (membership.all_nodes.length !== membership.cluster_nodes.length) return false

  // Check internal_replication_jobs is 0 on each node
  for (const host of hosts) {
    const systemRaw = await fetch(`https://${host}:5984/_node/_local/_system`, auth).then(r => r.json())
    const system = asSystemResponse(systemRaw)
    if (system.internal_replication_jobs > 0) return false
  }

  return true
}
```

### Dry-Run Mode

When `-dryRun` is set, the script performs **all queries** but skips destructive operations:

**Executed in dry-run:**
- Load and validate `resizeCluster.json`
- Unlock Bitwarden and retrieve passwords
- Query DigitalOcean API for current droplet sizes
- Check CouchDB cluster sync status (`/_membership`, `/_node/_local/_system`)
- Report which nodes would be skipped (already at target size)

**Skipped in dry-run:**
- SSH commands (stop couchdb, shutdown)
- DigitalOcean resize API calls
- DigitalOcean power-on API calls

This allows you to verify credentials, connectivity, and cluster health before committing to the resize.

### Script Location

Place the script at `edge-devops/src/bin/resizeCluster.ts`.

