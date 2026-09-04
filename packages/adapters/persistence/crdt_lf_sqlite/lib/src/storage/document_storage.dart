import 'dart:async';

import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';
import 'package:crdt_lf_sqlite/src/storage/change_storage.dart';
import 'package:crdt_lf_sqlite/src/storage/snapshot_storage.dart';
import 'package:crdt_lf_sqlite/src/transaction.dart';
import 'package:sqlite3/sqlite3.dart' as sq;

/// The changes and snapshots of one document, in a SQLite database.
///
/// It adds a real
/// [transaction] to the shared contract: the work inside one either all lands
/// or none of it does.
class CRDTSqliteDocumentStorage extends CRDTDocumentStorage {
  /// Creates the storage of the document [changes] and [snapshots] belong to,
  /// on [database].
  CRDTSqliteDocumentStorage({
    required this.database,
    required CRDTSqliteChangeStorage changes,
    required CRDTSqliteSnapshotStorage snapshots,
  }) : super(changes: changes, snapshots: snapshots);

  /// The database both halves write to.
  final sq.Database database;

  /// Runs [body] in one SQLite transaction.
  ///
  /// Nests: a batch that opens a transaction of its own keeps working inside
  /// this one, because both are savepoints. A [body] that returns without
  /// suspending — every storage method here does — is carried through without
  /// suspending, so no other document can write inside this transaction.
  @override
  FutureOr<T> transaction<T>(FutureOr<T> Function() body) =>
      runInTransaction(database, body);

  /// Does nothing, and that is the whole of it.
  ///
  /// One database holds every document, so closing it here would take the
  /// others down with it. 
  @override
  void close() {}
}
