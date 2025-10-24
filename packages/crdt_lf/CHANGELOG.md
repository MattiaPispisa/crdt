## [2.1.0]

### Added
- Added `change` operation to `CRDTFugueTextHandler` and `CRDTTextHandler` [12](https://github.com/MattiaPispisa/crdt/issues/12)

### Changed

- chore: improved Fugue text handler change implementation

## [2.0.0] - 2025-09-16

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

## [1.0.0] - 2025-08-18

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
- `documentId` to `CRDTDocument`, specified document identity to remove ambiguity between peer and document [38](https://github.com/MattiaPispisa/crdt/issues/38)
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

## [0.8.0] - 2025-07-08

### Added
- Added `update` operation for every handler [30](https://github.com/MattiaPispisa/crdt/issues/30)

## [0.7.1] - 2025-06-26

### Changed
- Update documentation

## [0.7.0+1] - 2025-06-14

### Fixed
- Chore: update readme links

## [0.7.0] - 2025-06-14

### Added
- `CRDTDocument.mergeSnapshot` to merge a snapshot with the current snapshot
- `CRDTDocument.import` to import changes and snapshots with a single method and different strategies

### Changed
- On changes pruning, if a change has a dependency on a pruned change, the dependency is removed to preserve integrity

## [0.6.1] - 2025-06-02

### Fixed

- Fix snapshot initialization for handlers that return a non primitive value

## [0.6.0] - 2025-05-10

**Breaking**

- `Operation.toPayload` is now a `Map<String, dynamic>` instead of `dynamic` (every operation was already returning a `Map<String, dynamic>`)

### Added

- `CRDTMapHandler`: a new handler for maps [13](https://github.com/MattiaPispisa/crdt/issues/13)

### Changed

- chore: apply linter rules
- chore: more documentation on public api

## [0.5.1] - 2025-05-08

### Fixed
- Fix folder name clash with gitignore rules 

## [0.5.0] - 2025-05-07

**Breaking**
- rename `document.import` in `document.binaryImportChanges`
- rename `document.export` in `document.binaryExportChanges`

### Added
- Snapshot implementation [14](https://github.com/MattiaPispisa/crdt/issues/14)
- Version vector (foundational for building snapshots)

### Fixed
- Fix Fugue tree insertion 

## [0.4.0] - 2025-04-29

### Changed
- chore: move test utils under `helpers` folder

## [0.3.0] - 2025-04-21

### Added
- `CRDTDocument` expose `localChanges` stream to listen to local changes [18](https://github.com/MattiaPispisa/crdt/issues/18)
- [flutter_example](https://github.com/MattiaPispisa/crdt/tree/main/packages/crdt_lf/flutter_example) 
contains a routing with a basic example for each use case (currently only todo list)[16](https://github.com/MattiaPispisa/crdt/issues/16)
- Split Fugue algorithm from text handler [4](https://github.com/MattiaPispisa/crdt/issues/4)

## [0.2.0] - 2025-04-09

### Added
- Tests [6](https://github.com/MattiaPispisa/crdt/issues/6)
  
### Fixed
- Fix cached value in handlers

## [0.1.0] - 2025-04-01

Initial release

### Added
- CRDTDocument with ChangeStore and Frontiers
- CRDTTextHandler
- CRDTListHandler
- CRDTFugueTextHandler
