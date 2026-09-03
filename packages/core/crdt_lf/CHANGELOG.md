## [Unreleased](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v4.2.0/packages/crdt_lf)

**Date:** --

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf-v4.1.0+1...crdt_lf-v4.2.0)

### Added

- **Undo and redo**, through the new `CRDTUndoManager`: an undo writes the opposite operation instead of
  removing a change, so it takes back your own edit and leaves everyone else's alone. [56](https://github.com/MattiaPispisa/crdt/issues/56)
  An inverse is anchored to the history it was built against, so pruning that history drops both stacks —
  `garbageCollect`, and `takeSnapshot` unless you pass `pruneHistory: false`. Use `pruneHistory: false` to
  checkpoint a document and keep its undo history.

### Changed

- A disposed document now refuses `garbageCollect` and `reconstruct`
  with a `DocumentDisposedException`, like every other method that writes to it.

### Fixed

- Disposing a `HistorySession` now ends the delta streams of the handlers it handed out, so a `watch()` subscriber is told the stream is over instead of waiting on one that can never fire again.

## [4.1.0+1](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v4.1.0+1/packages/crdt_lf)

**Date:** 2026-08-29

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf-v4.1.0...crdt_lf-v4.1.0+1)

### Fixed

- chore: fixed changelog

## [4.1.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v4.1.0/packages/crdt_lf)

**Date:** 2026-08-29

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf-v4.0.0...crdt_lf-v4.1.0)

### Added

- A handler publishes **deltas**: `watch()` gives one event per change describing how the handler's
  observable state moved, so a consumer keeps its own projection without reading `handler.value`. [132](https://github.com/MattiaPispisa/crdt/issues/132)

### Changed

- The Fugue tree groups elements into **runs**: elements one peer wrote with consecutive counters,
  adjacent in the sequence, now share a single node. Typing 100 000 characters builds 782 nodes
  instead of 100 000, which is **8× less memory** (371 → 48 bytes per element) and **up to 4× less
  time** wherever a document is built or loaded: appending 50 000 elements 30.1 ms → 9.4 ms,
  restoring 100 000 from a snapshot 93.3 ms → 22.7 ms. [125](https://github.com/MattiaPispisa/crdt/issues/125)
- A change costs about 20% less memory to hold.
- `runInTransaction`, `importChanges`, `binaryImportChanges`, `applyChange`, `createChange` and
  `import` take an optional `origin`, reported back on `HandlerDelta.origin`. It is how a consumer
  that writes drops its own echo, and how a sync manager marks what arrived from the network. It
  never travels, so it costs nothing on the wire. A `HandlerReset` carries none.

## [4.0.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v4.0.0/packages/crdt_lf)

**Date:** 2026-08-18

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf-v3.5.0...crdt_lf-v4.0.0)

### Changed

- Text handlers index by runes (code points), not UTF-16 code units. [106](https://github.com/MattiaPispisa/crdt/issues/106)
- New operation layer: a handler declares its own operation kinds.
  A handler decodes them by overriding `operationDecoders`, a plain kind-to-decoder map, instead of implementing dispatch by hand. [129](https://github.com/MattiaPispisa/crdt/issues/129)
- `update` on `CRDTFugueTextHandler` and `CRDTFugueListHandler` keeps the identity of the element
  instead of replacing it. [127](https://github.com/MattiaPispisa/crdt/issues/127)
- `Snapshot` carries a schema version, and so does every per-handler blob inside it. [130](https://github.com/MattiaPispisa/crdt/issues/130)
- `incrementCachedState` takes an optional `DeltaSink`. [132](https://github.com/MattiaPispisa/crdt/issues/132)
- `Handler` is a `base` class: extend it, do not implement it.
- A deleted element keeps its value, its place and the id of the change that removed it, in the
  tree and in the snapshot, so it can be put back whole.

### Breaking

A v3 document does not open in v4 — not from its history, not from a snapshot, not from the bytes an
adapter saved — so peers have to move together and existing documents have to be recreated; the
[README](https://github.com/MattiaPispisa/crdt/tree/main/packages/core/crdt_lf#migrating-from-3x-to-40) lists the
renamed and removed symbols. The Dart floor moves to `>=3.0.0`.

## [3.5.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v3.5.0/packages/crdt_lf)

**Date:** 2026-08-02

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf-v3.4.3...crdt_lf-v3.5.0)

### Performance

- **Every handler** now folds a remote change into the state it already holds,
  as long as that change is newer than everything folded in so far. A change that
  arrives from the past still forces a recompute.
  Measured on one remote change followed by a read: `CRDTTextHandler` on 30 000
  characters 417 µs → 13 µs, `CRDTMapHandler` on 5 000 keys 3.04 ms → 5 µs,
  Fugue text on 30 000 characters 19.6 ms → 0.69 ms. [121](https://github.com/MattiaPispisa/crdt/issues/121)
- Handlers whose state does not depend on the order changes arrive in keep their
  cached state **even when the change comes from the past**, which is what
  concurrent editing produces. This covers `CRDTFugueTextHandler`,
  `CRDTFugueListHandler`, `CRDTListRefHandler`, `CRDTORSetHandler` and
  `CRDTORMapHandler`. Measured on one such change followed by a read: OR-set on
  5 000 values 4.33 ms → 114 µs, OR-map on 5 000 keys 5.87 ms → 0.25 ms. [121](https://github.com/MattiaPispisa/crdt/issues/121)

### Added

- `compareChangeOrder`, the `(hlc, author)` order changes are replayed in.

### Changed

- Reorganized the document and handler files so that the members only the
  framework calls no longer show up on a handler you hold..

## [3.4.3](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v3.4.3/packages/crdt_lf)

**Date:** 2026-08-01

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf-v3.4.2+1...crdt_lf-v3.4.3)

### Fixed

- Repeated insertions at the same index no longer come out in the wrong order. [117](https://github.com/MattiaPispisa/crdt/issues/117) (thx to @coltrane)
- `update` now anchors the replacement to the element it replaces rather than to its position in the visible text, so an update whose target was concurrently deleted is no longer dropped. [113](https://github.com/MattiaPispisa/crdt/issues/113) (thx to @pedersen)
- A document rebuilt from a snapshot alone no longer reissues element ids it has already used.
- Importing a snapshot now advances the document clock past the snapshot's version vector, as applying a change already did.
- Inserting at index `0` now lands first even when the head of the sequence sits in the left subtree of the tree root, the shape a pruned origin produces.
- Reinserting an element id that the tree already holds now always throws `DuplicateNodeException`.

### Performance

- Improved Fugue sequence walks efficiency: `values()` and `nodes()` are served straight from the positional index.
- Appending to a Fugue sequence is faster: the positional index now recognises that a sequential insertion lands at the edge of a block instead of searching the block for it.

## [3.4.2+1](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v3.4.2+1/packages/crdt_lf)

**Date:** 2026-07-26

- Documentation release: refreshes the CHANGELOG and docs published on pub.dev. No functional changes since `3.4.2`.

## [3.4.2](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v3.4.2/packages/crdt_lf)

**Date:** 2026-07-21

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf-v3.4.1...crdt_lf-v3.4.2)

### Fixed

- **Fugue text handler only:** reading a large document no longer risks a stack
  overflow. The Fugue tree's in-order traversal was recursive, so a long run of
  consecutive inserts (e.g. repeated pasting) grew a deep chain that overflowed
  the call stack — sooner on Flutter web. It is now iterative.

## [3.4.1](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v3.4.1/packages/crdt_lf)

**Date:** 2026-07-20

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf-v3.4.0+2...crdt_lf-v3.4.1)

### Fixed

- Non-BMP characters (emoji, mathematical alphanumerics, …) no longer corrupt to U+FFFD (`�`): the text handlers split text per UTF-16 code unit, so a surrogate pair's halves were `utf8.encode`d separately and each lone surrogate became the replacement character (surfacing only on export/import or a snapshot reload). Text values are now serialized with a WTF-8 codec that round-trips the full Unicode range losslessly (the change is **backward compatible**: WTF-8 is byte-identical to UTF-8 for all well-formed text). [103](https://github.com/MattiaPispisa/crdt/issues/103) (thx to @pedersen)

## [3.4.0+2](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v3.4.0+2/packages/crdt_lf)

**Date:** 2026-07-19

- Documentation release: refreshes the CHANGELOG and docs published on pub.dev. No functional changes since `3.4.0`.

## [3.4.0+1](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v3.4.0+1/packages/crdt_lf)

**Date:** 2026-07-18

- Documentation release: refreshes the CHANGELOG and docs published on pub.dev. No functional changes since `3.4.0`.

## [3.4.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v3.4.0/packages/crdt_lf)

**Date:** 2026-07-17

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf-v3.3.0...crdt_lf-v3.4.0)

### Added

- `CRDTDocument.changeCountForHandler(handlerId)` — the number of changes produced by a handler, answered in O(1) from the existing per-handler index without allocating a list (it can decrease when history is pruned).
- `CRDTDocument.revisionForHandler(handlerId)` — a per-handler monotonic revision that grows every time the handler's observable state may have changed: a change targeting it is applied (local or imported), or a snapshot carrying its state is imported/merged. It never decreases (history pruning does not affect it), so equal readings guarantee the state did not change in between — the single signal reactive bindings should watch.
- `stablePositionAt(index)` / `indexOfStablePosition(position)` on the Fugue sequence handlers (`CRDTFugueTextHandler`, `CRDTFugueListHandler`) — stable caret/cursor anchors: the anchor is the `FugueElementID` of the element left of the caret, keeps pointing at it across concurrent edits (a deleted anchor resolves to where the element used to be), is serializable (`FugueElementID.toBytes`/`fromBytes`) for sharing with peers (remote cursors) and resolve in O(sqrt(n)) (like all operations in Fugue, thanks to the `sqrt_decomposition` algorithm introduced in version `3.2.0`). Resolution returns `null` for an element unknown to the document so callers can fall back to their own mapping.

## [3.3.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v3.3.0/packages/crdt_lf)

**Date:** 2026-07-14

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf-v3.2.1...crdt_lf-v3.3.0)

### Added

- Extended the `compound` compaction system for more handlers. 
    - `CRDTTextHandler` and `CRDTListHandler` collapse adjacent deletions (forward "Delete" and backward "Backspace" runs); 
    - `CRDTListHandler` collapses consecutive updates at the same index; 
    - `CRDTMapHandler` and `CRDTRegisterHandler` collapses consecutive writes to the same key (`set`/`update`/`delete`) into a single equivalent operation; 
    - `CRDTRegisterHandler` collapses consecutive sets into the last write. 

## [3.2.1](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v3.2.1/packages/crdt_lf)

**Date:** 2026-06-27

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf-v3.2.0...crdt_lf-v3.2.1)

### Fixed

- Nested handlers failed to reconstruct (and therefore to sync) in dart2js-minified builds (e.g. Flutter web `--release`), because handler type identity relied on `runtimeType.toString()` (an opaque `"minified:..."` token there). Introduced the stable `Handler.handlerType` tag used for routing, snapshot manifest, `HandlerRef`s and factory keys — defaults to `runtimeType.toString()` (non-breaking), overridden with a constant by built-in handlers, with an optional `handlerType` constructor argument for generic handlers.

## [3.2.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf-v3.2.0/packages/crdt_lf)

**Date:** 2026-06-25

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf-v3.1.0...crdt_lf-v3.2.0)

### Added

- `CRDTFugueListHandler<T>` — a list handler that uses the Fugue algorithm to minimize interleaving of concurrent edits. Like `CRDTListHandler<T>` it is generic over `T` with an optional `ValueCodec<T>`. [72](https://github.com/MattiaPispisa/crdt/issues/72)
- Added `CRDTFugueMovableListHandler<T>`, a list CRDT that combines Fugue's interleaving-minimizing insertion with an explicit `move(from, to)` operation that preserves the moved element's identity across concurrent reorderings (implements the algorithm from Kleppmann, *Moving Elements in List CRDTs*, PaPoC 2020). [26](https://github.com/MattiaPispisa/crdt/issues/26)
- It is possible to recursively nest “handlers,” which allow for real-world modeling. The following handlers have been added: `CRDTListRefHandler`, `CRDTMapRefHandler`, and `CRDTMovableListRefHandler`, which, instead of handling values, allow for the nesting of additional handlers. [74](https://github.com/MattiaPispisa/crdt/issues/74)
- `CRDTRegisterHandler<T>` — a single-value last-writer-wins register (the scalar counterpart of the collection handlers). Use it for a standalone mergeable value (flag, number, non-collaborative string), e.g. as a scalar field of a nested node.

### Changed

- **Performance**: `FugueTree` now answers position↔node queries through a square-root-decomposition positional index (`sqrt_decomposition`) instead of a full in-order traversal, so locating, inserting, deleting and updating a node by position costs O(√n) instead of O(n) (Performing 1,000 operations in the `FugueListHandler` reduces the execution time from  ~121ms to ~34ms). [71](https://github.com/MattiaPispisa/crdt/issues/71)
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
- [flutter_example](https://github.com/MattiaPispisa/crdt/tree/main/packages/core/crdt_lf/flutter_example) 
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
