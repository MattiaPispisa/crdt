# CRDT LF Hive

[![crdt_lf_hive_badge][crdt_lf_hive_badge]](https://pub.dev/packages/crdt_lf_hive)
[![License: MIT][license_badge]][license_link]

A [Hive](https://pub.dev/packages/hive) storage implementation for [CRDT LF](https://pub.dev/packages/crdt_lf) objects, providing efficient persistence for Change and Snapshot objects with document-scoped organization.

## Features

- **Complete Hive Adapters**: All necessary type adapters for CRDT objects (`Change`, `Snapshot`, `PeerId`, `OperationId`, `VersionVector`, etc.)
- **Easy Initialization**: One-line setup with `CRDTHive.initialize()`
- **Flexible Data Serialization**: Choose between JSON encoding or custom Hive adapters for generic data types
- **Document-Scoped Storage**: Optional utilities that organize data by document ID for better isolation and performance
- **Batch Operations**: Efficient bulk save/load operations for changes and snapshots

## Quick Start

### 1. Initialize Hive with CRDT Adapters

```dart
import 'package:hive/hive.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';

void main() async {
  // Initialize Hive
  Hive.init('./my_app_data');
  
  // Register all CRDT adapters
  CRDTHive.initialize();
  
  // Your app code here...
}
```

### 2. Basic Usage with Manual Box Management

```dart
import 'package:crdt_lf/crdt_lf.dart';
import 'package:hive/hive.dart';

// Open boxes manually
final changeBox = await Hive.openBox<Change>('changes');
final snapshotBox = await Hive.openBox<Snapshot>('snapshots');

// Store and retrieve changes
final change = /* your change */;
await changeBox.put(change.id.toString(), change);
final retrievedChange = changeBox.get(change.id.toString());
```

### 3. Using Document-Scoped Storage (Recommended)

```dart
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';

final documentId = 'my-document-id';

// Open storage for a specific document
final changeStorage = await CRDTHive.openChangeStorageForDocument(documentId);
final snapshotStorage = await CRDTHive.openSnapshotStorageForDocument(documentId);

// Or open both at once
final documentStorage = await CRDTHive.openStorageForDocument(documentId);
```

## Document-Scoped Storage

The library provides optional storage utilities that organize data by document ID. Each document gets its own dedicated Hive boxes, improving isolation and performance.

### CRDTChangeStorage

Manages `Change` objects for a specific document:

```dart
final changeStorage = await CRDTHive.openChangeStorageForDocument('doc-123');

// Save individual changes
await changeStorage.saveChange(change);

// Batch save multiple changes
await changeStorage.saveChanges([change1, change2, change3]);

// Load all changes for the document
final changes = changeStorage.getChanges();

// Delete changes
await changeStorage.deleteChange(change);
await changeStorage.deleteChanges([change1, change2]);

// Storage info
print('Total changes: ${changeStorage.count}');
print('Is empty: ${changeStorage.isEmpty}');
```

### CRDTSnapshotStorage

Manages `Snapshot` objects for a specific document:

```dart
final snapshotStorage = await CRDTHive.openSnapshotStorageForDocument('doc-123');

// Save snapshots
await snapshotStorage.saveSnapshot(snapshot);
await snapshotStorage.saveSnapshots([snapshot1, snapshot2]);

// Retrieve snapshots
final snapshot = snapshotStorage.getSnapshot('snapshot-id');
final allSnapshots = snapshotStorage.getSnapshots();

// Check existence
if (snapshotStorage.containsSnapshot('snapshot-id')) {
  // Snapshot exists
}
```

## Data Serialization Options

The `useDataAdapter` parameter in `CRDTHive.initialize()` controls how generic data types in CRDT operations are serialized:

### Default Mode (useDataAdapter: false)

Generic data is serialized using JSON encoding:

```dart
CRDTHive.initialize(); // useDataAdapter defaults to false

// Data like List<String>, Map<String, dynamic> will be JSON-encoded
final listHandler = CRDTListHandler<String>(document, 'items');
listHandler.insert(0, 'Hello World'); // Stored as JSON
```

### Custom Adapter Mode (useDataAdapter: true)

Generic data uses custom Hive adapters for better performance and type safety:

```dart
class MyCustomDataAdapter extends TypeAdapter<MyCustomData> {
  @override
  final int typeId = 200;

  @override
  ListValue read(BinaryReader reader) {
    // ...
  }

  @override
  void write(BinaryWriter writer, ListValue obj) {
    // ...
  }
}

// Register your custom adapters first
Hive.registerAdapter(MyCustomDataAdapter());

// Then initialize with custom adapter support
CRDTHive.initialize(useDataAdapter: true);

// Now your custom types will use their adapters
final listHandler = CRDTListHandler<MyCustomData>(document, 'items');
listHandler.insert(0, MyCustomData(value: 'test')); // Uses MyCustomDataAdapter
```

## Complete Example

A complete example with a custom data type and adapter is available [here](https://github.com/MattiaPispisa/crdt/blob/main/packages/crdt_lf_hive/example/main.dart).

## Box Naming Convention

When using document-scoped storage, boxes are named using the pattern:
- Changes: `{boxName}_{documentId}` (default: `changes_{documentId}`)
- Snapshots: `{boxName}_{documentId}` (default: `snapshots_{documentId}`)

This ensures each document has isolated storage while allowing custom box name prefixes.

## Storage Management

### Cleanup Operations

```dart
// Close all CRDT-related boxes
await CRDTHive.closeAllBoxes();

// Delete all data for a specific document
await CRDTHive.deleteDocumentData('doc-123');

// Delete a specific box
await CRDTHive.deleteBox('changes_doc-123');
```

### Box Customization

```dart
// Custom box names
final changeStorage = await CRDTHive.openChangeStorageForDocument(
  'doc-123',
  boxName: 'my_custom_changes',
);

final documentStorage = await CRDTHive.openStorageForDocument(
  'doc-123',
  changesBoxName: 'custom_changes',
  snapshotsBoxName: 'custom_snapshots',
);
```

## Important Notes

- **Document-scoped storage utilities are optional** - you can manage Hive boxes manually if preferred
- **Custom box organization** - the provided utilities use a specific box-per-document pattern, but you can implement your own organization strategy
- **Type ID conflicts** - ensure your custom adapters use unique type IDs

## Roadmap
A roadmap is available in the [project](https://github.com/users/MattiaPispisa/projects/1) page. The roadmap provides a high-level overview of the project's goals and the current status of the project.


[crdt_lf_hive_badge]: https://img.shields.io/pub/v/crdt_lf_hive.svg
[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT