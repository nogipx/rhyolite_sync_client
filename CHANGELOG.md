## [1.2.1] - 2026-04-13

### Features

- storage quota + streaming blob upload/download (core)


## [1.2.0] - 2026-04-10

### Features

- add vault repair flow (obsidian)
- add server timestamp for deterministic leaf ordering (graph)
- add deleteNodes RPC to remove orphaned nodes from server (core)
- prune side branches on startup for all files (core)
- rewrite sync client as three BLoCs with in-process bus (core)

### Bug Fixes

- notify and retry when vault lock is released (core)
- add lease lock to sync flow (core)
- prune all file nodes from graph on startup, not just registry (core)
- push delete record before removing from file registry (core)
- two-pass apply to handle out-of-order records from server (graph)
- two-pass graph build to handle out-of-order records (core)
- in-process notify bus calls (core)
- handle missing blobs gracefully instead of null crash (core)

### Refactoring

- replace SyncEngine internals with BLoC facade (core)
- file change event merge files (core)
- make use cases pure — graph mutated only via apply/markSynced (graph)

### Other

- add token bucket rate limiter for outbound RPC calls (core)
- optimize large vault startup and sync (core)


## [1.1.1] - 2026-04-07

### Other

- add section about bundled sqlite3mc (obsidian)


## [1.1.0] - 2026-04-07

### Features

- inline sqlite3mc.wasm as base64 in main.js (obsidian)


## [1.0.0] - 2026-04-05

### Features

- add logging and message field to RestoreSubscriptionResponse (account)
- block disposable email providers on signup (account)
- normalize email on signup to prevent trial abuse via aliases (account)

### Refactoring

- replace print logs with RpcLogger, disable in production (obsidian)
- replace inline styles with CSS classes via bootstrapPlugin extraCss (obsidian)
- centralize collection names and improve restore subscription UX (account)
