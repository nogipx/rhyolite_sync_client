# rhyolite_graph

DAG-based file versioning and sync tracking for Rhyolite Sync (Obsidian Sync analog).

---

## Purpose

Provides a graph data structure to track the causal history of file operations across multiple
devices. The graph is NOT responsible for conflict resolution, diff computation, or network sync —
it is a pure data/query layer.

---

## Core Concepts

### Graph = Full History

The graph stores the complete causal history of all file operations. Current vault state is a
*derived view* (read the leaves). The graph is **append-only** — history is never deleted or
modified.

### Nodes = Identity, Data = Payload

Built on `data_manage`'s `IGraph<Data>`:
- `Node` subclasses carry only identity (stable UUID key)
- `NodeData` sealed class carries the actual payload
- Graph type: `IGraph<NodeData>`

### Tree Topology (single-parent)

`IGraph` enforces single-parent per node. This is sufficient because conflict resolution uses
**rebase** (linear history replay), not merge commits. No multi-parent needed.

---

## Node Types

```
VaultNode   — root of the graph, represents the vault
FileNode    — one per file, stable UUID key (independent of path)
ChangeNode  — file content changed
MoveNode    — file renamed/moved
DeleteNode  — file deleted (tombstone)
```

### Graph Structure

```
VaultNode
└── FileNode (UUID)         ← direct child of VaultNode
    └── ChangeNode          ← first operation
        └── MoveNode        ← chained (Option B: linked list)
            └── ChangeNode  ← leaf = current state of the file
```

- `FileNode` chains operations as children of each other (not flat children of `FileNode`)
- Leaf node = current state
- `getLeaves()` from `IGraph` gives current state of all files

---

## NodeData Sealed Class

```
NodeData (sealed)
├── VaultData    — name: String
├── FileData     — path: String
├── ChangeData   — contentHash: String, timestamp: DateTime, deviceId: String
├── MoveData     — fromPath: String, toPath: String, timestamp: DateTime, deviceId: String
└── DeleteData   — timestamp: DateTime, deviceId: String
```

- Content is stored **externally** (blob storage). Graph stores only hashes.
- `contentHash` references external blob.
- `deviceId` is a String UUID.
- `timestamp` is `DateTime`.

---

## Type Hierarchy

```
IGraphReadable              shared query API
├── ActualGraph             + append-only mutations
└── StagedGraph             + conflict resolution API
```

### IGraphReadable (shared queries)

- `liveFiles()` — files where leaf is NOT `DeleteNode`
- `currentState(fileId)` — latest `NodeData` (leaf of chain)
- `history(fileId)` — ordered chain of nodes from `FileNode` to leaf
- `findByPath(path)` — `FileNode` by current path

### ActualGraph

- Always valid and conflict-free
- Append-only mutations:
  - `addFile(uuid, path)`
  - `appendChange(fileId, contentHash, deviceId, timestamp)`
  - `appendMove(fileId, fromPath, toPath, deviceId, timestamp)`
  - `appendDelete(fileId, deviceId, timestamp)`

### StagedGraph

- Result of merging two `ActualGraph` instances
- May contain unresolved conflicts
- Exposes same query API as `ActualGraph`
- Cannot be merged again — must be resolved first
- API:
  - `conflicts` → `List<FileConflict>`
  - `isResolved` → `bool`
  - `resolve(fileId, resolution)` — mark one conflict as resolved
  - `commit()` → `ActualGraph` — throws if `!isResolved`

### FileConflict

- `fileId` — UUID of the conflicting file
- `commonAncestor` — last shared node before divergence
- `branchMine` — chain from common ancestor (local device)
- `branchTheirs` — chain from common ancestor (remote device)

---

## GraphMerger (separate class)

```
GraphMerger.merge(ActualGraph mine, ActualGraph theirs) → StagedGraph
```

Not a method on the graph — merger is logic, graph is data.

---

## Full Sync Flow

```
ActualGraph(mine) + ActualGraph(theirs)
  → GraphMerger.merge()
  → StagedGraph (clean nodes + unresolved conflicts)
  → StagedGraph.resolve(fileId, resolution) × N
  → StagedGraph.commit()
  → new ActualGraph
```

---

## Conflict Cases

### Per-FileNode conflicts (same base, diverged chains)

| mine \ theirs | Change        | Move                      | Delete                        |
|---------------|---------------|---------------------------|-------------------------------|
| **Change**    | rebase + patch | apply both (path + content) | unresolvable automatically  |
| **Move**      | apply both    | path collision             | unresolvable automatically    |
| **Delete**    | unresolvable  | unresolvable               | no conflict → deleted         |

### Structural/path-level conflicts

- **Path collision** — two different FileNode UUIDs end up with the same path after independent moves
- **Create vs Create** — same path, two new FileNodes with different UUIDs created independently
- **Patch failure** — diff-match-patch can't apply during rebase (context changed too much)

### No conflict cases

- **Identical graphs** — already in sync
- **Fast-forward** — one graph is a strict prefix of the other → append missing nodes, no rebase

---

## Conflict Resolution Strategy

- Rebase-style: replay diverged chain on top of the other client's latest state
- diff-match-patch used **operationally** (when computing/applying changes during sync)
- diff-match-patch is NOT stored in nodes — nodes store snapshots (content hashes)
- `Change vs Delete`, `Move vs Delete` have no automatic resolution — require external decision

---

## Implementation Order

1. `NodeData` sealed class + subtypes
2. `IGraphReadable` interface
3. `ActualGraph` wrapping `IGraph<NodeData>`
4. `FileConflict` + `StagedGraph`
5. `GraphMerger`