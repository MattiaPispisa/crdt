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
