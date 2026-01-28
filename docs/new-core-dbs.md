# Edge Core JS Database Requirements

## Background

Edge Core JS is the core library powering the Edge wallet application. It manages cryptocurrency wallets, accounts, and related data across multiple platforms. The library currently uses the disklet library for persistent storage, but a more capable database solution is needed to support complex queries and improve performance.

## Current Architecture

The existing storage layer uses the **disklet** library, which provides a unified file-system-like API across platforms:

- **Mobile (iOS/Android)**: Runs inside a headless WebView; disklet bridges to native code for iOS and Android storage APIs
- **Web Browser**: Uses localStorage
- **Node.js**: Uses native file system storage

Disklet provides simple file read/write operations but lacks query capabilities, indexing, and efficient data retrieval for complex use cases.

## Requirements

### Platform Support

The database must run in all environments where edge-core-js operates:

- iOS (headless WebView context)
- Android (headless WebView context)
- Node.js
- Web browser (standard browser context)

### Performance

- Fast read/write operations for wallet data
- Efficient storage with minimal overhead
- Support for concurrent access patterns

### API Style

- SQL or NoSQL (flexible based on best fit)
- JavaScript/TypeScript API
- Promise-based async interface preferred

### Query Capabilities

The database should support:

- Key-value lookups
- Range queries
- Filtering by multiple fields
- Indexing for frequently queried fields

## Constraints

- Must work within WebView JavaScript context on mobile (no native modules required)
- Should integrate with or replace the existing disklet architecture
- Must support offline-first operation (no network dependency for core functionality)
- Data must be persistable across app restarts

---

## Research Results

### 1. Dexie.js

**Overview**: Minimalistic IndexedDB wrapper library with 13k+ GitHub stars and active maintenance.

**Platform Compatibility**:
- Browser: Full support (IndexedDB backend)
- Node.js: Supported via fake-indexeddb or similar polyfills
- Mobile WebView: Full support (uses native IndexedDB)

**Query Capabilities**:
- Key-value lookups
- Range queries (greater than, less than, between)
- Compound indexes for multi-field queries
- WhereClause API for filtering (`where('field').equals(value)`)
- Collection methods: `filter()`, `sortBy()`, `limit()`, `offset()`
- No full SQL support

**Performance Characteristics**:
- Direct IndexedDB access with minimal overhead
- Efficient bulk operations
- Automatic indexing based on schema
- Transactions for atomic operations

**Integration Complexity**: Low - simple Promise-based API, TypeScript support, zero dependencies

---

### 2. sql.js (SQLite via WebAssembly)

**Overview**: SQLite compiled to WebAssembly/JavaScript. 13.5k GitHub stars, MIT licensed.

**Platform Compatibility**:
- Browser: Full support via WebAssembly
- Node.js: Supported (though native SQLite bindings recommended for performance)
- Mobile WebView: Supported, requires loading .wasm file

**Query Capabilities**:
- Full SQL support (SELECT, INSERT, UPDATE, DELETE, JOIN)
- Complex queries with subqueries, aggregations, GROUP BY
- CREATE INDEX for custom indexes
- Transactions (BEGIN, COMMIT, ROLLBACK)
- Triggers and views

**Performance Characteristics**:
- In-memory by default (no automatic persistence)
- Requires manual export/import for persistence
- WebAssembly provides near-native performance
- Memory usage scales with database size

**Integration Complexity**: Medium - requires WASM file loading, manual persistence layer needed, TypeScript types available via @types/sql.js

---

### 3. PouchDB

**Overview**: Document store inspired by CouchDB with built-in sync. 17.5k GitHub stars, most popular option.

**Platform Compatibility**:
- Browser: Full support (IndexedDB backend)
- Node.js: Full support (LevelDB backend)
- Mobile WebView: Full support

**Query Capabilities**:
- Key-value by document ID
- MapReduce views for custom indexes
- Mango queries (MongoDB-like syntax) with `find()` plugin
- Filtering, sorting, pagination
- No JOIN support (document store)

**Performance Characteristics**:
- Optimized for sync scenarios
- Revision tracking adds overhead
- Good read performance with proper indexing
- Bulk operations supported

**Integration Complexity**: Medium - larger bundle size, CouchDB sync adds complexity if not needed, schema-free (no enforced types)

---

### 4. RxDB

**Overview**: Reactive NoSQL database with multiple storage backends. Built on top of other databases (Dexie, PouchDB, etc.).

**Platform Compatibility**:
- Browser: IndexedDB, LocalStorage, OPFS backends
- Node.js: Filesystem, SQLite, FoundationDB backends
- Mobile WebView: Full support via IndexedDB

**Query Capabilities**:
- MongoDB-like Mango Query syntax
- `find()`, `findOne()`, `count()` methods
- Filtering, sorting, bulk operations
- Reactive queries with `$` observable (auto-updates on data change)
- Query optimizer and result caching

**Performance Characteristics**:
- Query caching and de-duplication
- Performance depends on underlying storage backend
- Schema validation adds some overhead
- Optimized for reactive use cases

**Integration Complexity**: High - abstraction layer over other databases, larger bundle, requires RxJS, TypeScript-first

---

### 5. LokiJS

**Overview**: In-memory JavaScript database. Lightweight and fast for in-memory operations.

**Platform Compatibility**:
- Browser: Full support (in-memory with optional persistence)
- Node.js: Full support
- Mobile WebView: Full support

**Query Capabilities**:
- MongoDB-like query syntax
- `find()`, `findOne()`, `where()` methods
- Filtering with operators ($eq, $gt, $lt, $in, etc.)
- Dynamic views for live-updating result sets
- Chained find operations

**Performance Characteristics**:
- Extremely fast (all data in memory)
- Persistence via adapters (IndexedDB, filesystem)
- Memory usage scales with data size
- Not suitable for large datasets

**Integration Complexity**: Low - simple API, no dependencies, but less actively maintained (last major release 2019)

---

### Recommendation Summary

| Database | SQL Support | Cross-Platform | Persistence | Bundle Size | Maintenance |
|----------|-------------|----------------|-------------|-------------|-------------|
| Dexie.js | No | Excellent | Built-in | Small | Active |
| sql.js | Full | Good | Manual | Medium | Active |
| PouchDB | No | Excellent | Built-in | Large | Active |
| RxDB | No | Excellent | Built-in | Large | Active |
| LokiJS | No | Excellent | Via adapters | Small | Limited |

**For edge-core-js**, the top recommendations are:

1. **Dexie.js** - Best balance of simplicity, cross-platform support, and query capabilities. Ideal if NoSQL queries are sufficient.

2. **sql.js** - Best choice if full SQL query support is required. Requires building a persistence layer on top of disklet.

3. **PouchDB** - Good if future sync capabilities with a CouchDB server are desired, but adds unnecessary complexity for local-only use.
