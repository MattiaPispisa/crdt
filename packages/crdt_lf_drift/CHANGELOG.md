## 0.1.0

### Initial Release

- Added Drift database support for CRDT LF objects
- Added CRDTDrift utility class for managing databases
- Added CRDTChangeStorage and CRDTSnapshotStorage utilities for managing Change and Snapshot objects
- Added reactive streams support for real-time data synchronization
- Added type converters for all CRDT objects (PeerId, OperationId, VersionVector, etc.)
- Added document-scoped organization with SQL indexes for performance 