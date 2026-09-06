import 'dart:async';

import 'package:crdt_lf_drift/src/database.dart';
import 'package:crdt_lf_drift/src/storage/change_storage.dart';
import 'package:crdt_lf_drift/src/storage/snapshot_storage.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';

/// The changes and snapshots of one document, in a drift database.
///
/// It adds a real [transaction] to the shared contract: the work inside one
/// either all lands, or none of it does.
class CRDTDriftDocumentStorage extends CRDTDocumentStorage {
  /// Creates the storage of the document [changes] and [snapshots] belong to,
  /// on [database].
  CRDTDriftDocumentStorage({
    required this.database,
    required CRDTDriftChangeStorage changes,
    required CRDTDriftSnapshotStorage snapshots,
  }) : super(changes: changes, snapshots: snapshots);

  /// The database both halves write to.
  final CRDTDriftDatabase database;

  /// Runs [body] in one drift transaction.
  ///
  /// drift hands the transaction to the statements [body] runs, so the two
  /// halves write inside it without being told about it.
  ///
  /// drift is asynchronous end to end, so a [body] that would have finished
  /// without suspending is wrapped rather than carried through.
  @override
  Future<T> transaction<T>(FutureOr<T> Function() body) =>
      database.transaction(() async => body());

  /// Does nothing: one database holds every document.
  ///
  /// Closing it here would take the other documents down with it. `CRDTDrift`
  /// closes the database itself.
  @override
  Future<void> close() async {}
}
