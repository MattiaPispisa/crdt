import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';

/// The [Snapshot]s of one document, as a backend keeps them.
///
/// The counterpart of [CRDTChangeStorage]. A snapshot is identified by its
/// [Snapshot.id]: saving one twice replaces it.
///
/// A document normally has one snapshot at a time, but the store holds a
/// collection: a write interrupted halfway can leave two. Each one describes
/// the whole document, so [CRDTDocumentPersistence] keeps the newest of them
/// on the next open and drops the rest.
///
/// Every method returns a [FutureOr], on the same terms as
/// [CRDTChangeStorage].
abstract interface class CRDTSnapshotStorage {
  /// The document these snapshots belong to.
  String get documentId;

  /// Saves [snapshot], replacing one with the same id.
  FutureOr<void> saveSnapshot(Snapshot snapshot);

  /// Saves [snapshots] in one batch.
  FutureOr<void> saveSnapshots(List<Snapshot> snapshots);

  /// The snapshot with the given [id], or `null` when there is none.
  FutureOr<Snapshot?> getSnapshot(String id);

  /// Every stored snapshot of this document, in no particular order.
  FutureOr<List<Snapshot>> getSnapshots();

  /// Whether a snapshot with the given [id] is stored.
  FutureOr<bool> containsSnapshot(String id);

  /// Deletes the snapshot with the given [id].
  ///
  /// Returns `true` when it was there, `false` when it was not.
  FutureOr<bool> deleteSnapshot(String id);

  /// Deletes the snapshots with the given [ids] in one batch.
  ///
  /// Returns how many were actually there. An id named twice in one batch
  /// counts once: the answer is how many were deleted, not how many were
  /// asked for.
  FutureOr<int> deleteSnapshots(List<String> ids);

  /// Deletes every snapshot of this document.
  FutureOr<void> clear();

  /// How many snapshots of this document are stored.
  FutureOr<int> get count;
}

/// The newest of [snapshots], or `null` when there is none.
///
/// A snapshot holds the whole state of every handler, so one is enough. There
/// is normally one on the store: [CRDTDocumentPersistence] drops the old one as
/// soon as the new one is written. A process killed between those two steps
/// leaves two, and this picks the one to restore from.
///
/// The choice is made on the version vector, never on the order the backend
/// returns rows in. Two snapshots whose vectors are concurrent — neither has
/// seen everything the other has — cannot be ordered, and the first of the two
/// is kept.
Snapshot? newestSnapshot(List<Snapshot> snapshots) {
  if (snapshots.isEmpty) {
    return null;
  }
  return snapshots.reduce(
    (a, b) => b.versionVector.isStrictlyNewerOrEqualThan(a.versionVector)
        ? b
        : a,
  );
}

/// The read-then-pick step a caller of a [CRDTSnapshotStorage] takes to
/// restore.
extension CRDTSnapshotStorageLatest on CRDTSnapshotStorage {
  /// The newest stored snapshot, or `null` when there is none.
  ///
  /// Reads every snapshot and picks with [newestSnapshot]. A caller that
  /// already holds the list calls [newestSnapshot] instead.
  FutureOr<Snapshot?> getLatestSnapshot() {
    return getSnapshots().chain(newestSnapshot);
  }
}
