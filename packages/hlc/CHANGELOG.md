## [1.0.0]

### Added

- Can set a `maxDrift` for `receiveEvent` (added `ClockDriftException`)
- `asDateTime` to get the logical/physical part of the timestamp as a `DateTime` object
- `nextTimestamp` and `merge` to update the clock without mutating the original instance

### Changed
- chore: setup .github/workflows and update coverage links [33](https://github.com/MattiaPispisa/crdt/issues/33)
- Assert non-negative logical time and counter

## [0.3.1] - 2025-06-26

### Changed

- Update documentation

## [0.3.0] - 2025-05-10

### Changed

- chore: apply linter rules
- chore: more documentation on public api

## [0.2.0] - 2025-04-27

### Added

- `happenedAfter`
- `operator >=`
- `operator <=`
- `operator >`
- `operator <`

## [0.1.3] - 2025-04-21

### Changed

- Updated `CHANGELOG.md`

## [0.1.2] - 2025-04-04

### Changed

- Shorter `pubspec.yaml` description

## [0.1.1] - 2025-04-02

### Added

- Tests, 100% coverage

### Changed

- Improved static analysis
- chore: update README

### Fixed

- chore: fix repository link

## [0.1.0] - 2025-04-01

Initial release

### Added
- Local event handling
- Message exchange between peers
- Causality detection
- Serialization to/from 64-bit integers
- Thread-safe implementation
- Zero dependencies
