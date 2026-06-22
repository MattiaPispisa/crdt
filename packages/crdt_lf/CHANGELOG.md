## [Unreleased](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v3.2.0/packages/crdt_lf)

**Date:** 

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf-v3.1.0...crdt_lf-v3.2.0)

### Added

- `CRDTFugueListHandler<T>` — a list handler that uses the Fugue algorithm to minimize interleaving of concurrent edits. Like `CRDTListHandler<T>` it is generic over `T` with an optional `ValueCodec<T>`. [72](https://github.com/MattiaPispisa/crdt/issues/72)
- Added `CRDTFugueMovableListHandler<T>`, a list CRDT that combines Fugue's interleaving-minimizing insertion with an explicit `move(from, to)` operation that preserves the moved element's identity across concurrent reorderings (implements the algorithm from Kleppmann, *Moving Elements in List CRDTs*, PaPoC 2020). [26](https://github.com/MattiaPispisa/crdt/issues/26)
- It is possible to recursively nest “handlers,” which allow for real-world modeling. The following handlers have been added: `CRDTListRefHandler`, `CRDTMapRefHandler`, and `CRDTMovableListRefHandler`, which, instead of handling values, allow for the nesting of additional handlers. [74](https://github.com/MattiaPispisa/crdt/issues/74)

### Changed

- **Performance**: requesting the operations of a handler now scales linearly with that handler's own operations instead of with the whole oplog. `Handler.operations()` reads from the new per-handler index in `ChangeStore` rather than scanning every change, so resolving a handler's state — and therefore reading a nested tree of handlers — no longer degrades quadratically as the number of handlers grows (resolving an 800-node nested document drops from ~1.3s to ~32ms).
- **Performance**: `CRDTDocument.importChanges` updates the handler caches once per batch instead of once per applied change, removing the O(handlers × changes) cost on large imports (importing and resolving an 800-node nested document drops from ~2.0s to ~120ms).
- chore: improved documentation highlighting how data can be modelled. The differences between the handlers and the available options are emphasized through concrete examples.

## [3.1.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v3.1.0/packages/crdt_lf)
**Date:** 2026-06-13

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf-v3.0.0...crdt_lf-v3.1.0)

Performance-focused release: handler caches are now updated in place instead of being deep-copied on every operation, and several core algorithms were rewritten to remove quadratic behavior. [70](https://github.com/MattiaPispisa/crdt/issues/70)

### Added
- `DAG.getAncestorsOfAll(Iterable<OperationId>)` — single traversal with a shared visited set over multiple sources; `exportChanges(from:)` now uses it instead of one walk per frontier head.
- `Frontiers.reset(Iterable<OperationId>)` — replaces the frontier content directly.

### Changed

- **Performance**: `CRDTORSetHandler`, `CRDTORMapHandler`, `CRDTListHandler` and `CRDTMapHandler` no longer deep-copy their cached state on every operation; the cache is mutated in place (the OR-Set handler benchmark drops from ~180ms to ~27ms for 1000 operations on a fresh document).
- **Performance**: `CRDTFugueTextHandler` resolves its nodes and text lazily on read instead of re-traversing the whole tree after every operation.
- **Performance**: `CRDTTextHandler` replays history on a mutable list of code units and applies incremental updates with a single string concatenation instead of multiple `StringBuffer` round-trips.
- **Performance**: `ChangeStore.exportChangesNewerThan` answers from a lazily-built per-peer index sorted by clock (binary search) instead of scanning every stored change — this is the sync-server hot path (~500x faster on a 50k-change store).
- **Performance**: `ChangeStore.prune` only rebuilds the changes whose dependencies were actually pruned, preserving object identity for untouched changes.
- **Performance**: `CRDTDocument` topological sort uses a `ListQueue` (`removeFirst`) instead of `List.removeAt(0)`, removing quadratic behavior on large imports.
- **Performance**: `DAG.getLCA` filters the lowest common ancestors through the children sets instead of re-running full ancestor walks.
- `CRDTListHandler.value` and `CRDTMapHandler.value` now consistently return the handler's internal collection on both the cached and the recomputed path (previously the recomputed path returned a copy). Treat the returned collection as read-only.
- `CacheableStateProvider.cachedState` may now be mutated in place between reads (live view rather than per-operation snapshot).

### Fixed

- `Frontiers.merge` compared operations with a total-order HLC comparison instead of causal dominance, so concurrent heads of different peers collapsed to the single operation with the highest clock after every `DAG.prune` (i.e. after every pruning snapshot or garbage collection). Frontiers now keep one head per peer (operations of the same peer are totally ordered; operations of different peers are concurrent), and `DAG.prune`/`DAG.merge` recompute the frontier from the structure of the graph. The document `version` no longer under-reports after a snapshot with concurrent peers.
- `DAG` constructor mis-used `Map.fromIterable` when building the version vector from a non-empty node map, throwing a runtime type error. The vector is now built explicitly taking the maximum clock per peer.

## [3.0.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v3.0.0/packages/crdt_lf)
**Date:** 2026-06-11

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf-v2.5.0...crdt_lf-v3.0.0)

**Breaking changes**

The internal data model has migrated from JSON to a compact binary encoding. Changes, operations, peer IDs, and clock values are now stored and transmitted as raw bytes. Views over the binary data are created lazily on demand rather than eagerly decoded into Dart objects. This results in measurably better throughput and reduced memory fragmentation. [64](https://github.com/MattiaPispisa/crdt/issues/64)

- `Change.fromJson` and `Change.toJson` removed. Use `Change.fromBytes(Uint8List)` and `Change.toBytes()` instead.
- `Change.fromPayload({..., payload: Map<String, dynamic>})` renamed to `Change.fromPayloadBytes({..., payloadBytes: Uint8List})`. The payload is now an opaque binary blob.
- `Change.payload` (`Map<String, dynamic>`) removed. Use `Change.payloadBytes()` returning `Uint8List`.
- `CRDTDocument.binaryExportChanges` return type changed from `List<int>` to `Uint8List`.
- `CRDTDocument.binaryImportChanges` parameter type changed from `List<int>` to `Uint8List`.
- `Operation.handlerIdFrom(payload: Map)` removed. Operation identity is now derived from the binary envelope via `OperationEnvelopeCodec`.
- `Snapshot.data` type changed from `Map<String, dynamic>` to `Map<String, Uint8List>`. Each entry is the opaque binary blob produced by the corresponding handler's `getSnapshotState()` and is owned by that handler.
- `Snapshot.toJson` / `Snapshot.fromJson` removed. Use `Snapshot.toBytes()` / `Snapshot.fromBytes(Uint8List)` instead.
- `SnapshotProvider.getSnapshotState()` return type changed from `dynamic` to `Uint8List`. Each handler is now responsible for encoding its own state to bytes (typically by reusing its `ValueCodec<T>`) and for decoding it back from `lastSnapshot()`.
- `SnapshotProvider.lastSnapshot()` return type changed from `dynamic` to `Uint8List?`.
- `VersionVector.toJson` / `VersionVector.fromJson` removed. Use `VersionVector.toBytes()` / `VersionVector.fromBytes(Uint8List)` instead.

### Added

- `Change.toBytes()` and `Change.fromBytes(Uint8List)` — binary serialization for a single change, replacing the removed `toJson`/`fromJson`.
- `VersionVector.toBytes()` and `VersionVector.fromBytes(Uint8List)` — compact binary encoding for version vectors.
- `Snapshot.toBytes()` and `Snapshot.fromBytes(Uint8List)` — binary serialization for snapshots.
- `CRDTDocument.registeredHandlers` — read-only map of handlers currently registered on the document, intended for introspection and tooling.

### Changed

- `ChangeStore` now indexes changes by `OpIdKey` instead of `OperationId`, eliminating redundant object allocation on lookup.
- Several hot-path performance improvements: `HybridLogicalClock.toUint8List` now uses integer arithmetic instead of floating-point, `PeerId.fromUint8List` avoids regex validation and intermediate string allocation, `DAG.getAncestors` was converted from O(n²) BFS to O(n) DFS, and frequently-used `OperationType` instances are now cached lazily on each handler.

### Fixed

- Fixed `CRDTFugueTextHandler` throwing `CrdtException: Node already exists` after restoring document state via `binaryImportChanges`, `importChanges`, or `importSnapshot`. [65](https://github.com/MattiaPispisa/crdt/issues/65) (thx to @coltrane)

## [2.5.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v2.5.0/packages/crdt_lf)
**Date:** 2026-01-03

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf-v2.4.0...crdt_lf-v2.5.0)

### Added
- Added `garbageCollect` to `CRDTDocument` to prune the document history. It prunes the document history up to the given version vector. `VersionVector.intersection` can be used to compute the minimum common version vector that contains the minimum clock for each peer. [61](https://github.com/MattiaPispisa/crdt/issues/61)
- Added `fromVersionVector` to `CRDTDocument.exportChanges` to export changes that are newer than a given version vector.

### Changed
- Implemented hashCode memoization for `PeerId`, `FugueElementId`, `Change`, `ORHandlerTag`, `ORMapEntry`, `OperationId`, `OperationType`. Constructors are no longer const, resulting in faster equality checks and reduced CPU usage during heavy parsing or collection lookups.
- chore: improved example. Can now time travel and garbage collect the document history.

## [2.4.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v2.4.0/packages/crdt_lf)
**Date:** 2025-12-29

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf-v2.3.0...crdt_lf-v2.4.0)

### Added

- Added `HistorySession` to `CRDTDocument` to navigate the history of the document. It allows "Time travel" functionality by moving a temporal cursor back and forth through the changes. Can be called using `document.toTimeTravel()` [55](https://github.com/MattiaPispisa/crdt/issues/55)

### Changed
- CRDTDocument now extends `BaseCRDTDocument` instead of implementing it directly. `Handler`s now use `BaseCRDTDocument` instead of `CRDTDocument`.
- Improved `CRDTDocument` disposal management. After disposal, all operations on the document will throw `DocumentDisposedException` [57](https://github.com/MattiaPispisa/crdt/issues/57)
- Reuse tag creation logic in `CRDTORMapHandler` and `CRDTORSetHandler` to avoid code duplication [54](https://github.com/MattiaPispisa/crdt/issues/54)
- chore: improved documentation

## [2.3.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v2.3.0/packages/crdt_lf)
**Date:** 2025-12-24

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf-v2.2.0...crdt_lf-v2.3.0)

### Added

- Added `initialClock` to `CRDTDocument` constructor
- Added `prepareMutation` to `CRDTDocument` to prepare the system to perform a mutation

### Fixed

- `CRDTORMapHandler` and `CRDTORSetHandler` now refresh clock ("prepareMutation") before creating a tag [52](https://github.com/MattiaPispisa/crdt/issues/52) (thx to @gborges9)

## [2.2.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v2.2.0/packages/crdt_lf)
**Date:** 2025-11-22

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf-v2.1.0...crdt_lf-v2.2.0)

### Changed
- chore: improved documentation about version vector
- Can import snapshot even if there are newer changes in the document

### Fixed
- chore: fixed references links
- Fix `CRDTDocument.applyChange` to correctly handle dependencies that were pruned from the DAG [50](https://github.com/MattiaPispisa/crdt/issues/50)

## [2.1.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v2.1.0/packages/crdt_lf)
**Date:** 2025-10-31

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf-v2.0.0...crdt_lf-v2.1.0)

### Added
- Added `change` operation to `CRDTFugueTextHandler` and `CRDTTextHandler` [12](https://github.com/MattiaPispisa/crdt/issues/12)
- Added `CRDTORMapHandler` [41](https://github.com/MattiaPispisa/crdt/issues/41)

### Changed

- chore: improved Fugue text handler change implementation

### Fixed

- Fixed deserialization of Map values in `CRDTFugueTextHandler` operations

## [2.0.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v2.0.0/packages/crdt_lf)
**Date:** 2025-09-16

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf-v1.0.0...crdt_lf-v2.0.0)

**Breaking changes**
- Changed `CRDTFugueTextHandler` operations payload

### Added

- Created a set of mixins to be used by handlers to optimize performance during operation insertions.
- Thrown `HandlerAlreadyRegisteredException` when a handler is registered twice
- Added `TransactionManager` to manage transactional batching of notifications and local changes emission [43](https://github.com/MattiaPispisa/crdt/issues/43)
- Added `compound` "system" to compact consecutive operations during transaction [45](https://github.com/MattiaPispisa/crdt/issues/45)
- Added `CRDTORSetHandler` [42](https://github.com/MattiaPispisa/crdt/issues/42)

### Changed

- On `importChanges` listeners of `updates` are notified only one times at import end
- `Handlers` now not invalidate cache when an operation is applied due to the new mixins system. This greatly improves the computation of the handler value as it is persisted much more often.
- chore: improved handlers benchmark system

### Fixed
- `CRDTMapHandler` updating an absent key is ignored

## [1.0.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v1.0.0/packages/crdt_lf)
**Date:** 2025-08-18

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf-v0.8.0...crdt_lf-v1.0.0)

**Breaking changes**
Create a set of exception classes to be used across the library. Replace `StateError` with `CrdtException` and its subclasses.

- `applyChange`: throws `CausallyNotReadyException` instead of `StateError` when a change's dependencies are not met;
- On import when a cycle is detected among changes throws `ChangesCycleException` instead of `StateError`;
- On add node when a node already exists throws `DuplicateNodeException` instead of `StateError`;
- On add node when a dependency is missing throws `MissingDependencyException` instead of `StateError`;
- On Fugue tree insertion when a node already exists throws `DuplicateNodeException` instead of `Exception`.

Removed redundant `hlc` from `Change`. `change.hlc` is also available as getter [37](https://github.com/MattiaPispisa/crdt/issues/37)

Hlc in version vector is now serialized as string instead of int64. This avoids precision loss when serialized as JSON for web interoperability.

### Added
- `documentId` to `CRDTDocument`, specified document identity to remove ambiguity between peer and document [38](https://github.com/MattiaPispisa/crdt/issues/38) (thx to @Jei-sKappa)
- `toString` to `Snapshot` and `VersionVector`
- added a stream to `CRDTDocument` to be notified of every change (changes, snapshots, merges, ...)
- added `mutable` and method to `VersionVector` to create mutable copies
- added a export changes method to `CRDTDocument` to export changes that are newer than a given version vector

### Changed
- chore: setup .github/workflows and update coverage links [33](https://github.com/MattiaPispisa/crdt/issues/33)
- chore: update readme with recommended approach for complex handler types
- chore: update topological sort implementation [3](https://github.com/MattiaPispisa/crdt/issues/3)
- chore: added benchmarks

### Fixed
- Fix `CRDTFugueTextHandler` to ensure state is synchronized before performing operations [39](https://github.com/MattiaPispisa/crdt/issues/39)
- Fix readme reference links
- Fix double hlc increment on `CRDTDocument.createChange`
- Fix snapshot initialization for handlers that return a non primitive value

## [0.8.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v0.8.0/packages/crdt_lf)
**Date:** 2025-07-08

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf-v0.7.1...crdt_lf-v0.8.0)

### Added
- Added `update` operation for every handler [30](https://github.com/MattiaPispisa/crdt/issues/30)

## [0.7.1](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v0.7.1/packages/crdt_lf)
**Date:** 2025-06-26

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf-v0.7.0...crdt_lf-v0.7.1)

### Changed
- Update documentation

## [0.7.0+1](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v0.7.0+1/packages/crdt_lf)
**Date:** 2025-06-14

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf-v0.7.0...crdt_lf-v0.7.0+1)

### Fixed
- Chore: update readme links

## [0.7.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v0.7.0/packages/crdt_lf)
**Date:** 2025-06-14

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf-v0.6.1...crdt_lf-v0.7.0)

### Added
- `CRDTDocument.mergeSnapshot` to merge a snapshot with the current snapshot
- `CRDTDocument.import` to import changes and snapshots with a single method and different strategies

### Changed
- On changes pruning, if a change has a dependency on a pruned change, the dependency is removed to preserve integrity

## [0.6.1](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v0.6.1/packages/crdt_lf)
**Date:** 2025-06-02

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf-v0.6.0...crdt_lf-v0.6.1)

### Fixed

- Fix snapshot initialization for handlers that return a non primitive value

## [0.6.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v0.6.0/packages/crdt_lf)
**Date:** 2025-05-10

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf-v0.5.1...crdt_lf-v0.6.0)

**Breaking**

- `Operation.toPayload` is now a `Map<String, dynamic>` instead of `dynamic` (every operation was already returning a `Map<String, dynamic>`)

### Added

- `CRDTMapHandler`: a new handler for maps [13](https://github.com/MattiaPispisa/crdt/issues/13)

### Changed

- chore: apply linter rules
- chore: more documentation on public api

## [0.5.1](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v0.5.1/packages/crdt_lf)
**Date:** 2025-05-08

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf-v0.5.0...crdt_lf-v0.5.1)

### Fixed
- Fix folder name clash with gitignore rules 

## [0.5.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v0.5.0/packages/crdt_lf)
**Date:** 2025-05-07

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf-v0.4.0...crdt_lf-v0.5.0)

**Breaking**
- rename `document.import` in `document.binaryImportChanges`
- rename `document.export` in `document.binaryExportChanges`

### Added
- Snapshot implementation [14](https://github.com/MattiaPispisa/crdt/issues/14)
- Version vector (foundational for building snapshots)

### Fixed
- Fix Fugue tree insertion 

## [0.4.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v0.4.0/packages/crdt_lf)
**Date:** 2025-04-29

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf-v0.3.0...crdt_lf-v0.4.0)

### Changed
- chore: move test utils under `helpers` folder

## [0.3.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v0.3.0/packages/crdt_lf)
**Date:** 2025-04-21

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf-v0.2.0...crdt_lf-v0.3.0)

### Added
- `CRDTDocument` expose `localChanges` stream to listen to local changes [18](https://github.com/MattiaPispisa/crdt/issues/18)
- [flutter_example](https://github.com/MattiaPispisa/crdt/tree/main/packages/crdt_lf/flutter_example) 
contains a routing with a basic example for each use case (currently only todo list)[16](https://github.com/MattiaPispisa/crdt/issues/16)
- Split Fugue algorithm from text handler [4](https://github.com/MattiaPispisa/crdt/issues/4)

## [0.2.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v0.2.0/packages/crdt_lf)
**Date:** 2025-04-09

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf-v0.1.0...crdt_lf-v0.2.0)

### Added
- Tests [6](https://github.com/MattiaPispisa/crdt/issues/6)
  
### Fixed
- Fix cached value in handlers

## [0.1.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v0.1.0/packages/crdt_lf)
**Date:** 2025-04-01

**Initial release**

### Added
- CRDTDocument with ChangeStore and Frontiers
- CRDTTextHandler
- CRDTListHandler
- CRDTFugueTextHandler
