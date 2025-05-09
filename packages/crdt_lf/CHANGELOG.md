## [0.6.0] - 2025-05-10

**Breaking**

- `Operation.toPayload` is now a `Map<String, dynamic>` instead of `dynamic` (every operation was already returning a `Map<String, dynamic>`)

### Added

- `CRDTMapHandler`: a new handler for maps

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