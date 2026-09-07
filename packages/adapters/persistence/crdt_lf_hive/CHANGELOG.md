## [0.5.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_hive-v0.5.0/packages/adapters/persistence/crdt_lf_hive)

**Date:** 2026-09-07

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf_hive-v0.4.0...crdt_lf_hive-v0.5.0)

### Changed

- **The storages implement the shared contract** from the new
  [`crdt_lf_persistence`](https://pub.dev/packages/crdt_lf_persistence), re-exported here so one
  import stays enough. Code written against a storage now runs on any adapter, and
  `CRDTDocumentPersistence` keeps a whole document on disk for you — see that package's README.

- **`CRDTHive.open()` gives a `CRDTHiveBackend`**, the `CRDTStorageBackend` of this adapter. Hive
  cannot list its boxes, so the backend keeps a small registry box (`documents` by default), written
  the first time a document is opened. **A document stored before this registry existed is not on
  the list until it is opened once** — its data is untouched either way.

- **`deleteDocumentData` is now `deleteDocument`**, the name the contract uses. The static one leaves
  the registry alone; `CRDTHiveBackend.deleteDocument` forgets the document as well, identity
  included.

- **`CRDTChangeStorage` and `CRDTSnapshotStorage` are now `CRDTHiveChangeStorage` and
  `CRDTHiveSnapshotStorage`**, matching the other adapters. The old names belong to the contract they
  implement. `CRDTDocumentStorage` comes from `crdt_lf_persistence` and is re-exported, so the import
  path does not change.

- **`getChanges`, `getSnapshots`, `count` and `containsSnapshot` stay synchronous** — a Hive box
  keeps its entries in memory, and the return types say so. **`await` on them is no longer valid,
  drop it.** Writes go through the box journal and stay asynchronous.

- **`CRDTHivePeerIdStorage` keeps the `PeerId` a document writes under**, so a restart no longer adds
  a peer to the version vector. Open it with `CRDTHive.openPeerIdStorageForDocument` and read it
  before building the document; every document shares one `peer_ids` box, keyed by document id.

- `getChanges` takes `newerThan` and `upTo`, both `VersionVector`s: what a vector has not seen, what
  it has seen, or the range between them.

- `isEmpty` and `isNotEmpty` are gone from both storages. Use `count`.

- `openStorageForDocument` returns a `CRDTHiveDocumentStorage`, whose `close()` closes that
  document's two boxes and nothing else. Hive has no transactions, so `transaction()` keeps its
  default and just runs the body.

- Requires `crdt_lf: ^4.2.0`.

### Fixed

- **Deleting an open document no longer hangs on the web.** A box is an IndexedDB database, and the
  browser waits for every connection to close before it deletes one. `deleteDocument` now closes the
  two boxes first. `deleteBox` is unchanged — close the box yourself if you opened it.

- **A document id no longer goes into a box name as it is.** Hive lower-cases box names and refuses
  non-ASCII ones, so `Note` and `note` merged into one document and an accented id tripped an
  assert. Ids are now escaped: anything outside `a-z`, `0-9` and `-` becomes `~` plus the hex of the
  byte, over UTF-8. **A lower-case ASCII id keeps exactly the box name it had**, so a 0.4.0 store
  reads back unchanged; only the ambiguous or broken ids move. `documentBoxNameFor` is exported, for
  a migration written by hand.

## [0.4.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_hive-v0.4.0/packages/adapters/persistence/crdt_lf_hive)

**Date:** 2026-08-16

- Requires `crdt_lf: ^4.0.0` instead of `>=3.0.0 <5.0.0`.
- The Dart floor moves to `>=3.0.0`, which `crdt_lf` now needs.

## [0.3.1](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_hive-v0.3.1/packages/crdt_lf_hive)

**Date:** 2026-07-28

Widens the `crdt_lf` constraint to `>=3.0.0 <5.0.0`. No functional changes, and no migration of existing databases.

## [0.3.0+2](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_hive-v0.3.0+2/packages/crdt_lf_hive)

**Date:** 2026-07-19

- Documentation release: refreshes the CHANGELOG and docs published on pub.dev. No functional changes since `0.3.0`.

## [0.3.0+1](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_hive-v0.3.0+1/packages/crdt_lf_hive)

**Date:** 2026-07-18

- Documentation release: refreshes the CHANGELOG and docs published on pub.dev. No functional changes since `0.3.0`.

## [0.3.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_hive-v0.3.0/packages/crdt_lf_hive)
**Date:** 2026-06-11

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf_hive-v0.2.3...crdt_lf_hive-v0.3.0)

**Breaking changes**

- `ChangeAdapter` no longer accepts the `useDataAdapter` parameter, which is removed. The adapter now always serializes `Change` objects via `Change.toBytes()` / `Change.fromBytes()`.
- `SnapshotAdapter` is now a thin wrapper around `Snapshot.toBytes()` / `Snapshot.fromBytes()`. The `useDataAdapter` constructor parameter has been removed: `Snapshot.data` is always serialized via `JsonValueCodec` (its values must be JSON-serializable).
- **Storage format changed**: existing Hive boxes written with `0.x` adapters are not readable by this version. A one-time migration (read with old adapter, write with new) is required before upgrading.
- Removed adapters that are no longer part of the persistence pipeline (changes and snapshots are stored as opaque binary blobs):
  - `PeerIdAdapter` / `kPeerIdAdapter`
  - `HybridLogicalClockAdapter` / `kHybridLogicalClockAdapter`
  - `OperationIdAdapter` / `kOperationIdAdapter`
  - `VersionVectorAdapter` / `kVersionVectorAdapter`
  - `FugueElementIDAdapter` / `kFugueElementIDAdapter`
  - `FugueValueNodeAdapter` / `kFugueValueNodeAdapter`
- `CRDTHive.initialize` signature reduced to `({int? changeTypeId, int? snapshotTypeId})`. The `useDataAdapter`, `peerIdTypeId`, `hybridLogicalClockTypeId`, `operationIdTypeId`, `versionVectorTypeId`, `fugueElementIdTypeId`, `fugueValueNodeTypeId` parameters have been removed.
- Updated `crdt_lf` dependency to `^3.0.0`.

### Changed

- `ChangeAdapter` rewritten to use the compact binary format introduced by `crdt_lf` 3.0.0. Stores a raw byte list per change instead of JSON-encoded fields, reducing storage size and eliminating runtime JSON parsing.
- `SnapshotAdapter` rewritten as a single-byte-list wrapper around `Snapshot.toBytes()` / `Snapshot.fromBytes()`. No more recursive `BinaryWriter`/`BinaryReader` calls into nested types.

### Removed

- `OperationIdAdapter`, `PeerIdAdapter`, `HybridLogicalClockAdapter`, `VersionVectorAdapter`, `FugueElementIDAdapter`, `FugueValueNodeAdapter` and their `k*Adapter` type-id constants. With `Change` and `Snapshot` serialized as binary blobs, no nested Hive adapters are involved in the pipeline.
- `useDataAdapter` flag from `SnapshotAdapter` and `CRDTHive.initialize`. Use `Snapshot.data` with JSON-serializable values instead.

## [0.2.3](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_hive-v0.2.3/packages/crdt_lf_hive)
**Date:** 2025-11-22

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf_hive-v0.2.2...crdt_lf_hive-v0.2.3)

### Changed
- chore: added code coverage references

## [0.2.2](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_hive-v0.2.2/packages/crdt_lf_hive)
**Date:** 2025-10-30

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf_hive-v0.2.1...crdt_lf_hive-v0.2.2)

### Changed
- chore: more tests

## [0.2.1](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_hive-v0.2.1/packages/crdt_lf_hive)
**Date:** 2025-09-16

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf_hive-v0.2.0...crdt_lf_hive-v0.2.1)

### Changed
- chore: update `crdt_lf` dependency to support version `2.0.0`

## [0.2.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_hive-v0.2.0/packages/crdt_lf_hive)
**Date:** 2025-08-18

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf_hive-v0.1.0...crdt_lf_hive-v0.2.0)

**Breaking changes**
Due to the `Change` breaking change in `crdt_lf` 1.0.0, the `Change` adapter has been updated.

### Changed

- chore: update `crdt_lf` dependency to `^1.0.0`
- chore: update `hlc_dart` dependency to `^1.0.0`
- chore: update readme


## [0.1.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_hive-v0.1.0/packages/crdt_lf_hive)
**Date:** 2025-06-08

### Initial Release

- Added Hive adapters for CRDT LF objects [8](https://github.com/MattiaPispisa/crdt/issues/8)
- Added CRDTHive utility class for managing Hive boxes [8](https://github.com/MattiaPispisa/crdt/issues/8)
- Added CRDTChangeStorage and CRDTSnapshotStorage utilities for managing Change and Snapshot objects [8](https://github.com/MattiaPispisa/crdt/issues/8)
