---
name: Clean Up DB Requirements Doc
overview: Transform the raw prompt in `new-core-dbs.md` into a structured requirements document with clear sections for background, requirements, constraints, and a placeholder for research results.
todos:
  - id: rewrite-doc
    content: Rewrite new-core-dbs.md with proper requirements document structure
    status: completed
isProject: false
---

# New Core Database Requirements Document Cleanup

## Current State

The file [`docs/new-core-dbs.md`](docs/new-core-dbs.md) contains a raw research prompt with the following key information embedded:

- **Target**: edge-core-js library
- **Current storage**: disklet library (bridges to native on mobile, localStorage on web, filesystem on Node)
- **Environments**: iOS/Android webview, Node.js, web browser
- **Goal**: Add SQL or NoSQL database that's fast and efficient

## Proposed Structure

Rewrite as a proper requirements document:

```markdown
# Edge Core JS Database Requirements

## Background

Brief context about edge-core-js and why a database is needed.

## Current Architecture

- Disklet library overview
- Platform bridging details

## Requirements

### Platform Support
- iOS (headless WebView)
- Android (headless WebView)
- Node.js
- Web browser

### Performance
- Fast read/write operations
- Efficient storage

### API Style
- SQL or NoSQL (flexible)

## Constraints

- Must work within WebView JavaScript context on mobile
- Must integrate with existing disklet architecture or replace it

---

## Research Results

(To be completed)

For each database option, include:
- Platform compatibility details
- Query capabilities (what types of queries are supported)
- Performance characteristics
- Integration complexity
```

## Changes

1. Add proper markdown heading
2. Extract background context into its own section
3. Break out platform requirements explicitly
4. Add constraints section based on the architectural details mentioned
5. Add empty "Research Results" section at the end for future use

---

## Execution Log

**Completed**: Rewrote `new-core-dbs.md` as a structured requirements document.

**Changes made**:
- Added proper title: "Edge Core JS Database Requirements"
- Created Background section explaining edge-core-js purpose and need for database
- Created Current Architecture section detailing disklet library and platform bridging
- Created Requirements section with subsections:
  - Platform Support (iOS/Android WebView, Node.js, Web browser)
  - Performance (fast read/write, efficient storage, concurrent access)
  - API Style (SQL/NoSQL flexible, JS/TS API, Promise-based)
  - Query Capabilities (key-value, range queries, filtering, indexing)
- Created Constraints section (WebView compatibility, disklet integration, offline-first, persistence)
- Added Research Results placeholder with template for documenting each option

---

**Completed**: Added research results for 5 database options.

**Databases Researched**:
1. **Dexie.js** - IndexedDB wrapper, excellent cross-platform, NoSQL queries
2. **sql.js** - SQLite via WebAssembly, full SQL support, manual persistence
3. **PouchDB** - Document store with CouchDB sync, largest community
4. **RxDB** - Reactive NoSQL, multiple backends, higher complexity
5. **LokiJS** - In-memory database, fast but limited maintenance

**Top Recommendations**:
- Dexie.js for simplicity and balance
- sql.js if full SQL is required
- PouchDB if sync capabilities are needed later
