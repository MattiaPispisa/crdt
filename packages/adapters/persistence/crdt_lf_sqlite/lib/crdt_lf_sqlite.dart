/// A [sqlite3](https://pub.dev/packages/sqlite3) storage implementation for
/// CRDT (Conflict-free Replicated Data Type) objects.
///
/// This library provides storage utilities for persisting CRDT
/// Changes and Snapshots in a single SQLite database, organized by
/// document.
library;

export 'src/crdt_sqlite.dart';
export 'src/storage/change_storage.dart';
export 'src/storage/document_storage.dart';
export 'src/storage/snapshot_storage.dart';
