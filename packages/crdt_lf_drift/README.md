# CRDT LF Drift

[![pub package](https://img.shields.io/pub/v/crdt_lf_drift.svg)](https://pub.dev/packages/crdt_lf_drift)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://opensource.org/licenses/MIT)

A [Drift](https://pub.dev/packages/drift) database implementation for [CRDT LF](https://pub.dev/packages/crdt_lf) objects, providing efficient persistence for Change and Snapshot objects with reactive streams and document-scoped organization.

## Features

- **Complete Drift Integration**: All necessary table definitions and type converters for CRDT objects
- **Reactive Streams**: Real-time data synchronization with Drift's built-in stream support
- **Document-Scoped Storage**: Organize data by document ID with SQL indexes for optimal performance
- **Batch Operations**: Efficient bulk save/load operations for changes and snapshots
- **Type Safety**: Full type safety with generated Drift code
- **Multi-Platform**: Works on all platforms supported by Drift (iOS, Android, Web, Desktop)
- **SQL Queries**: Leverage the power of SQL for complex queries and filtering

## Quick Start

### 1. Add Dependencies

```yaml
dependencies:
  crdt_lf_drift: ^0.1.0
  sqlite3_flutter_libs: ^0.5.0  # For mobile platforms
```

### 2. Basic Usage

```dart
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_drift/crdt_lf_drift.dart';

void main() async {
  final documentId = 'my-document-id';

  // Open storage for a specific document
  final changeStorage = await CRDTDrift.openChangeStorageForDocument(
    documentId,
    databasePath: './my_app_data',
  );

  // Load existing changes and create document
  final document = CRDTDocument(peerId: PeerId.generate())
    ..importChanges(await changeStorage.getChanges());

  final textHandler = CRDTTextHandler(document, 'text');
  
  // Make changes
  textHandler.insert(0, 'Hello, World!');
  
  // Save changes
  final changesToSave = <Change>[];
  document.localChanges.listen(changesToSave.add);
  await changeStorage.saveChanges(changesToSave);
  
  // Clean up
  await CRDTDrift.closeAllDatabases();
}
```

## Document-Scoped Storage

The library provides storage utilities that organize data by document ID using SQL tables with proper indexing for performance.

### CRDTChangeStorage

Manages `Change` objects for a specific document:

```dart
final changeStorage = await CRDTDrift.openChangeStorageForDocument('doc-123');

// Save individual changes
await changeStorage.saveChange(change);

// Batch save multiple changes (more efficient)
await changeStorage.saveChanges([change1, change2, change3]);

// Load all changes for the document
final changes = await changeStorage.getChanges();

// Delete changes
await changeStorage.deleteChange(change);
await changeStorage.deleteChanges([change1, change2]);

// Storage info
final count = await changeStorage.count;
final isEmpty = await changeStorage.isEmpty;

// Reactive streams - get notified of changes in real-time
final changeStream = changeStorage.watchChanges();
changeStream.listen((changes) {
  print('Document now has ${changes.length} changes');
});
```

### CRDTSnapshotStorage

Manages `Snapshot` objects for a specific document:

```dart
final snapshotStorage = await CRDTDrift.openSnapshotStorageForDocument('doc-123');

// Save snapshots
await snapshotStorage.saveSnapshot(snapshot);
await snapshotStorage.saveSnapshots([snapshot1, snapshot2]);

// Retrieve snapshots
final snapshot = await snapshotStorage.getSnapshot('snapshot-id');
final allSnapshots = await snapshotStorage.getSnapshots();

// Check existence
if (await snapshotStorage.containsSnapshot('snapshot-id')) {
  // Snapshot exists
}

// Reactive streams
final snapshotStream = snapshotStorage.watchSnapshots();
snapshotStream.listen((snapshots) {
  print('Document has ${snapshots.length} snapshots');
});
```

## Database Management

### Multiple Databases

```dart
// Different documents can use different database files
final storage1 = await CRDTDrift.openChangeStorageForDocument(
  'doc-1',
  databasePath: './database1',
);

final storage2 = await CRDTDrift.openChangeStorageForDocument(
  'doc-2', 
  databasePath: './database2',
);

// Or use the same database with document isolation
final storage3 = await CRDTDrift.openChangeStorageForDocument('doc-3'); // default db
final storage4 = await CRDTDrift.openChangeStorageForDocument('doc-4'); // default db
```

### Database Lifecycle

```dart
// Close specific database
await CRDTDrift.closeDatabase('./my_database');

// Close all databases
await CRDTDrift.closeAllDatabases();

// Get existing database instance
final database = CRDTDrift.getDatabase('./my_database');

// Create test database (in-memory)
final testDb = CRDTDrift.createTestDatabase('test');
```

### Document Storage Utility

```dart
// Open both change and snapshot storage at once
final documentStorage = await CRDTDrift.openStorageForDocument('doc-123');

// Access individual storages
await documentStorage.changes.saveChange(change);
await documentStorage.snapshots.saveSnapshot(snapshot);
```

## Advanced Features

### Reactive Streams

Drift provides built-in reactive streams that automatically notify you when data changes:

```dart
// Watch for changes in real-time
final changeStream = changeStorage.watchChanges();
final subscription = changeStream.listen((changes) {
  // This fires whenever changes are added/removed/updated
  updateUI(changes);
});

// Don't forget to cancel the subscription
await subscription.cancel();
```

### Custom Queries

Since this uses Drift, you can access the underlying database for custom queries:

```dart
final database = CRDTDrift.getDatabase();
if (database != null) {
  // Custom query example: get changes created in the last hour
  final recentChanges = await (database.select(database.changes)
    ..where((tbl) => tbl.createdAt.isBiggerThanValue(
        DateTime.now().subtract(Duration(hours: 1))))
    ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]))
    .get();
}
```

### Type Converters

The library includes type converters for all CRDT objects:

- `PeerIdConverter` - Converts PeerId ↔ String
- `HybridLogicalClockConverter` - Converts HLC ↔ JSON String  
- `OperationIdConverter` - Converts OperationId ↔ JSON String
- `VersionVectorConverter` - Converts VersionVector ↔ JSON String

These are automatically used by the table definitions but can be used independently if needed.

## Performance Considerations

### Indexes

The library creates optimized indexes for common query patterns:

- `changes_document_id_idx` - For filtering changes by document
- `changes_operation_id_idx` - For looking up changes by operation ID
- `changes_created_at_idx` - For temporal queries
- `snapshots_document_id_idx` - For filtering snapshots by document
- `snapshots_created_at_idx` - For temporal snapshot queries

### Batch Operations

Always prefer batch operations for multiple inserts:

```dart
// ✅ Good - single transaction
await changeStorage.saveChanges([change1, change2, change3]);

// ❌ Avoid - multiple transactions
await changeStorage.saveChange(change1);
await changeStorage.saveChange(change2);
await changeStorage.saveChange(change3);
```

## Example

A complete example is available in the [example directory](example/main.dart), showing:
- Document initialization with existing data
- Making CRDT operations
- Saving changes to Drift
- Using reactive streams
- Proper cleanup

## Comparison with crdt_lf_hive

| Feature | crdt_lf_hive | crdt_lf_drift |
|---------|--------------|---------------|
| Storage Type | Key-Value (Hive) | Relational (SQLite) |
| Queries | Limited | Full SQL support |
| Reactive Streams | Manual | Built-in |
| Performance | Good for simple access | Better for complex queries |
| Cross-platform | Excellent | Excellent |
| Schema Evolution | Manual | Automated migrations |
| Memory Usage | Lower | Slightly higher |

## Migration from crdt_lf_hive

If you're migrating from `crdt_lf_hive`, the API is very similar:

```dart
// Before (Hive)
final changeStorage = await CRDTHive.openChangeStorageForDocument(documentId);
await CRDTHive.closeAllBoxes();

// After (Drift)  
final changeStorage = await CRDTDrift.openChangeStorageForDocument(documentId);
await CRDTDrift.closeAllDatabases();
```

The main differences:
- All storage operations are now `async` 
- Added reactive stream support with `watchChanges()` and `watchSnapshots()`
- Database path parameter instead of box names
- Additional SQL query capabilities

## Important Notes

- **All operations are async** - Drift operations return Futures
- **Reactive by design** - Use streams for real-time updates
- **Schema migrations** - Drift handles database schema evolution automatically
- **Resource management** - Remember to close databases when shutting down
- **Platform setup** - Follow Drift's platform-specific setup instructions

## Packages

Other components of the CRDT system:

- [crdt_lf](https://pub.dev/packages/crdt_lf) - Core CRDT implementation
- [crdt_lf_hive](https://pub.dev/packages/crdt_lf_hive) - Hive storage (alternative to this package)
- [crdt_socket_sync](https://pub.dev/packages/crdt_socket_sync) - Real-time synchronization
- [hlc_dart](https://pub.dev/packages/hlc_dart) - Hybrid logical clocks

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.