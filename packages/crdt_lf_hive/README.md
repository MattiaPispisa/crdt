# CRDT LF Hive

[![pub package](https://img.shields.io/pub/v/crdt_lf_hive.svg)](https://pub.dev/packages/crdt_lf_hive)

Hive adapters for [CRDT LF](https://pub.dev/packages/crdt_lf) library objects, providing persistence for Change and Snapshot objects.

## Features

- **Complete CRDT Persistence**: Serialize and deserialize all CRDT objects:
  - `Change` - Individual operations in the CRDT
  - `Snapshot` - Point-in-time states of the CRDT
  - `OperationId` - Unique identifiers for operations
  - `PeerId` - Peer identifiers 
  - `HybridLogicalClock` - Logical timestamps
  - `VersionVector` - Vector clocks for causality tracking

- **Storage Utilities**: High-level APIs for managing CRDT objects:
  - `CRDTChangeStorage` - Store and query changes
  - `CRDTSnapshotStorage` - Store and query snapshots
  - Time-based queries, batch operations, and more

- **Efficient Storage**: Optimized binary serialization via Hive adapters

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  crdt_lf_hive: ^1.0.0
  hive: ^2.2.3
```

## Quick Start

### 1. Initialize Hive

```dart
import 'package:crdt_lf_hive/crdt_lf_hive.dart';

// Initialize all CRDT adapters
CRDTHive.initialize();
```

### 2. Open Storage Boxes

```dart
// Open dedicated boxes for different object types
final changesBox = await CRDTHive.openChangesBox();
final snapshotsBox = await CRDTHive.openSnapshotsBox();

// Create storage utilities
final changeStorage = CRDTChangeStorage(changesBox);
final snapshotStorage = CRDTSnapshotStorage(snapshotsBox);
```

### 3. Store and Retrieve Objects

```dart
import 'package:crdt_lf/crdt_lf.dart';

// Create a change
final peerId = PeerId.generate();
final hlc = HybridLogicalClock.now();
final operationId = OperationId(peerId, hlc);

final change = Change.fromPayload(
  id: operationId,
  deps: <OperationId>{},
  hlc: hlc,
  author: peerId,
  payload: {
    'type': 'text_insert',
    'text': 'Hello CRDT!',
    'position': 0,
  },
);

// Store the change
await changeStorage.saveChange(change);

// Retrieve the change
final retrievedChange = changeStorage.getChange(operationId);
print(retrievedChange?.payload);
```

## API Reference

### CRDTHive

Main utility class for initialization and box management.

```dart
// Initialize adapters (call once at app startup)
CRDTHive.initialize();

// Open boxes
final changesBox = await CRDTHive.openChangesBox();
final snapshotsBox = await CRDTHive.openSnapshotsBox();

// Cleanup
await CRDTHive.closeAllBoxes();
await CRDTHive.deleteBox('changes');
```

### CRDTChangeStorage

Storage utility for managing `Change` objects.

```dart
final storage = CRDTChangeStorage(changesBox);

// Store operations
await storage.saveChange(change);
await storage.saveChanges([change1, change2, change3]);

// Retrieve operations
final change = storage.getChange(operationId);
final allChanges = storage.getAllChanges();
final changesByAuthor = storage.getChangesByAuthor(peerId);

// Time-based queries
final recentChanges = storage.getChangesInTimeRange(
  from: startTime,
  to: endTime,
);
final sortedChanges = storage.getChangesSortedByTime();
final mostRecent = storage.getMostRecentChange();

// Dependency queries
final dependentChanges = storage.getChangesDependingOn(operationId);

// Delete operations
await storage.deleteChange(operationId);
await storage.deleteChanges([id1, id2, id3]);
await storage.clear();

// Statistics
print('Count: ${storage.count}');
print('Empty: ${storage.isEmpty}');
```

### CRDTSnapshotStorage

Storage utility for managing `Snapshot` objects.

```dart
final storage = CRDTSnapshotStorage(snapshotsBox);

// Store operations
await storage.saveSnapshot(snapshot);
await storage.saveSnapshots([snapshot1, snapshot2]);

// Retrieve operations
final snapshot = storage.getSnapshot(snapshotId);
final allSnapshots = storage.getAllSnapshots();
final snapshotsByPeer = storage.getSnapshotsByPeer(peerId);

// Version-based queries
final newerSnapshots = storage.getSnapshotsNewerThan(versionVector);
final bestSnapshot = storage.getBestSnapshotForVersion(targetVersion);

// Time-based queries
final mostRecent = storage.getMostRecentSnapshot();
final sorted = storage.getSnapshotsSortedByTime();

// Cleanup operations
await storage.deleteSnapshot(snapshotId);
await storage.deleteOldSnapshots(keepCount: 5);
await storage.clear();
```

## Advanced Usage

### Custom Box Names

```dart
// Use custom box names for different document types
final todoChangesBox = await CRDTHive.openChangesBox(boxName: 'todo_changes');
final todoSnapshotsBox = await CRDTHive.openSnapshotsBox(boxName: 'todo_snapshots');

final todoChangeStorage = CRDTChangeStorage(todoChangesBox);
final todoSnapshotStorage = CRDTSnapshotStorage(todoSnapshotsBox);
```

### Batch Operations

```dart
// Efficient batch storage
final changes = [change1, change2, change3];
await changeStorage.saveChanges(changes);

// Batch deletion
final operationIds = [id1, id2, id3];
final deletedCount = await changeStorage.deleteChanges(operationIds);
```

### Snapshot Management

```dart
// Keep only the 10 most recent snapshots
final deletedCount = await snapshotStorage.deleteOldSnapshots(keepCount: 10);

// Find the best snapshot for a given version
final bestSnapshot = snapshotStorage.getBestSnapshotForVersion(targetVersion);
if (bestSnapshot != null) {
  // Use this snapshot as a starting point
  print('Best snapshot: ${bestSnapshot.id}');
}
```

## Type ID Reference

The library uses the following Hive type IDs:

| Type | ID |
|------|-----|
| PeerId | 100 |
| HybridLogicalClock | 101 |
| OperationId | 102 |
| VersionVector | 103 |
| Change | 104 |
| Snapshot | 105 |

Make sure these IDs don't conflict with your existing Hive adapters.

## Example

See the complete example in [example.dart](lib/src/example.dart) for a full demonstration of the library's capabilities.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details. 