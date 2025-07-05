## 1.0.0

### Initial Release

- **Complete CRDT Persistence**: Added Hive adapters for all CRDT objects:
  - `PeerId` - Peer identifier storage
  - `HybridLogicalClock` - Logical timestamp storage
  - `OperationId` - Operation identifier storage
  - `VersionVector` - Vector clock storage
  - `Change` - CRDT change operation storage
  - `Snapshot` - CRDT snapshot storage

- **Storage Utilities**: High-level APIs for managing CRDT objects:
  - `CRDTHive` - Main utility class for initialization and box management
  - `CRDTChangeStorage` - Storage utility for managing Change objects
  - `CRDTSnapshotStorage` - Storage utility for managing Snapshot objects

- **Rich Query Support**: 
  - Time-based queries for changes and snapshots
  - Author-based filtering for changes
  - Dependency tracking for changes
  - Version vector comparisons for snapshots
  - Batch operations for efficient storage

- **Storage Management Features**:
  - Automatic cleanup of old snapshots
  - Batch operations for performance
  - Storage statistics and metadata
  - Custom box names for multiple document types

- **Type Safety**: All adapters use unique type IDs (100-105) to prevent conflicts

- **Documentation**: Comprehensive README with examples and API reference

### Dependencies

- `crdt_lf`: Core CRDT library
- `hlc_dart`: Hybrid Logical Clock implementation
- `hive`: High-performance local storage
- `collection`: Dart collection utilities 