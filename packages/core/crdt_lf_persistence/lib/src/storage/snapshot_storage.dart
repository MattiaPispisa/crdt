import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';

/// The [Snapshot]s of one document, as a backend keeps them.
///
/// The counterpart of [CRDTChangeStorage]. A snapshot is identified by its
/// [Snapshot.id]: saving one twice replaces it.
///
/// A document normally has one snapshot at a time, but the store holds a
/// collection: a write interrupted halfway can leave two, and
/// [CRDTDocumentPersistence] folds them on the next open rather than guessing
/// which one to trust.
abstract interface class CRDTSnapshotStorage {
  /// The document these snapshots belong to.
  String get documentId;

  /// Saves [snapshot], replacing one with the same id.
  Future<void> saveSnapshot(Snapshot snapshot);

  /// Saves [snapshots] in one batch.
  Future<void> saveSnapshots(List<Snapshot> snapshots);

  /// The snapshot with the given [id], or `null` when there is none.
  Future<Snapshot?> getSnapshot(String id);

  /// Every stored snapshot of this document, in no particular order.
  Future<List<Snapshot>> getSnapshots();

  /// Whether a snapshot with the given [id] is stored.
  Future<bool> containsSnapshot(String id);

  /// Deletes the snapshot with the given [id].
  ///
  /// Returns `true` when it was there, `false` when it was not.
  Future<bool> deleteSnapshot(String id);

  /// Deletes the snapshots with the given [ids] in one batch.
  ///
  /// Returns how many were actually there.
  Future<int> deleteSnapshots(List<String> ids);

  /// Deletes every snapshot of this document.
  Future<void> clear();

  /// How many snapshots of this document are stored.
  Future<int> get count;
}
