/// A [drift](https://pub.dev/packages/drift) storage implementation for
/// CRDT (Conflict-free Replicated Data Type) objects.
///
/// This library provides storage utilities for persisting CRDT objects like
/// Changes and Snapshots in a single drift database, organized by document
/// via the `document_id` column.
library;

export 'src/crdt_drift.dart';
export 'src/database.dart' show CRDTDriftDatabase;
export 'src/storage/change_storage.dart';
export 'src/storage/document_storage.dart';
export 'src/storage/snapshot_storage.dart';
