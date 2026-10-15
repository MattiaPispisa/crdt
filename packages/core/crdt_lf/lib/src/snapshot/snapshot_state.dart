import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/snapshot/records.dart';
import 'package:crdt_lf/src/utils/bytes.dart';

/// The snapshot a document's history is replayed on, and the rules for
/// replacing it.
class SnapshotState {
  /// The snapshot held now; `null` before the first one.
  Snapshot? current;

  /// Whether [incoming] may replace the snapshot held now: it is newer than
  /// or equal to it for every peer, or nothing is held.
  bool shouldApply(Snapshot incoming) {
    final held = current;
    if (held == null) {
      return true;
    }
    return incoming.versionVector
        .isStrictlyNewerOrEqualThan(held.versionVector);
  }

  /// Merges [incoming] into the snapshot held now, holds the result and
  /// returns it.
  ///
  /// Throws a [ConcurrentSnapshotException], and holds what it held, when
  /// both hold a handler with different bytes at concurrent versions.
  Snapshot merge(Snapshot incoming) {
    final held = current;
    if (held == null) {
      return current = incoming;
    }
    if (_mergeLosesState(held, incoming)) {
      throw ConcurrentSnapshotException(
        currentId: held.id,
        incomingId: incoming.id,
      );
    }
    return current = SnapshotRecords.mergeKeepingRecords(held, incoming);
  }

  /// Whether merging the two would drop a handler's state: at concurrent
  /// versions, both hold it as different blobs, or as unfolded changes neither
  /// side holds all of.
  static bool _mergeLosesState(Snapshot a, Snapshot b) {
    if (a.versionVector.isStrictlyNewerOrEqualThan(b.versionVector) ||
        b.versionVector.isStrictlyNewerOrEqualThan(a.versionVector)) {
      return false;
    }
    final entriesA = SnapshotRecords.unfoldedEntriesOf(a);
    final entriesB = SnapshotRecords.unfoldedEntriesOf(b);
    final shared = SnapshotRecords.handlerIdsOf(a)
        .intersection(SnapshotRecords.handlerIdsOf(b));
    for (final id in shared) {
      final blobA = a.data[id];
      final blobB = b.data[id];
      final sameBlob = blobA == null || blobB == null
          ? blobA == blobB
          : bytesEqual(blobA, blobB);
      // On one blob, the side with more unfolded changes holds the other.
      final ordered =
          SnapshotRecords.entryHoldsAll(entriesA[id], entriesB[id]) ||
              SnapshotRecords.entryHoldsAll(entriesB[id], entriesA[id]);
      if (!sameBlob || !ordered) {
        return true;
      }
    }
    return false;
  }

  /// [history], the version of the changes on top of the snapshot, merged
  /// with the version of the snapshot held now.
  VersionVector versionVector(VersionVector history) {
    final held = current;
    return held == null ? history : history.merged(held.versionVector);
  }

  /// The version history may be pruned up to: what [protectUntil] and the
  /// snapshot held now have both seen. Empty when nothing is held.
  VersionVector prunableUpTo(VersionVector protectUntil) =>
      VersionVector.intersection([
        protectUntil,
        current?.versionVector ?? VersionVector({}),
      ]);

  /// A read-only copy of the snapshot held now; `null` when nothing is held.
  ///
  /// Writing to its [Snapshot.data] or its [Snapshot.versionVector] throws an
  /// [UnsupportedError].
  Snapshot? readOnlyCopy() {
    final held = current;
    if (held == null) {
      return null;
    }
    return Snapshot(
      id: held.id,
      versionVector: held.versionVector.immutable(),
      data: {
        for (final MapEntry(:key, :value) in held.data.entries)
          key: value.asUnmodifiableView(),
      },
    );
  }
}
