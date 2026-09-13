import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/snapshot/records.dart';
import 'package:crdt_lf/src/utils/bytes.dart';

/// Keeps track of the formats a document's data is written in.
///
/// Answers [describe] from the data rather than from the handlers, so a
/// document that has opened none still answers in full.
///
/// It stays off until someone asks. [start] reads the last snapshot's record
/// and walks the whole log once; from then on [fold] runs where a change
/// enters, so a change that arrives out of order is still counted.
class DataRequirementsTracker {
  /// What the data holds, by handler type.
  ///
  /// The kinds grow only: a change can add one, never take one away. So a
  /// prune keeps what the pruned changes had contributed, and a snapshot can
  /// carry the description forward (see [SnapshotRecords.capabilitiesKey]).
  /// The blob range is the one part that can be dropped again — see
  /// [replaceBlobVersions].
  final Map<String, HandlerFormats> _byType = {};

  /// The pairs already folded, holding the handler type as the bytes it
  /// appears as in an envelope.
  ///
  /// A document writes a handful of distinct pairs and then repeats them, so
  /// the list stays short and a change almost always matches one. That match
  /// is what keeps [fold] off the decode.
  final List<({Uint8List type, int kind})> _foldedKinds = [];

  bool _started = false;

  /// Whether the fold is running, so a change has to be handed to [fold] as it
  /// enters.
  ///
  /// Turned on by [CRDTDocument.describeDataRequirements] and by
  /// [CRDTDocument.takeSnapshot], which writes the record whether or not
  /// anyone ever asks. A document that snapshots therefore folds every change
  /// it applies from then on; one that does neither pays nothing.
  bool get isStarted => _started;

  /// Reads [lastSnapshot]'s record and every change [changes] yields, once.
  ///
  /// Does nothing on a tracker that is already started.
  void start({
    required Snapshot? lastSnapshot,
    required List<Change> Function() changes,
  }) {
    if (_started) {
      return;
    }
    // Set first: the walk below must not be folded twice if anything it
    // touches ends up applying a change.
    _started = true;

    readRecord(lastSnapshot);
    for (final change in changes()) {
      fold(change);
    }
  }

  /// Folds the record [snapshot] carries into what is known about the data.
  ///
  /// Does nothing for a snapshot that predates the record, or one whose record
  /// this build cannot read: an unreadable record is a reason to say less, not
  /// a reason to refuse the snapshot.
  void readRecord(Snapshot? snapshot) {
    final blob = snapshot?.data[SnapshotRecords.capabilitiesKey];
    if (blob == null) {
      return;
    }

    final DocumentRequirements record;
    try {
      record = SnapshotRecords.decodeRequirements(blob);
    } catch (_) {
      return;
    }

    for (final entry in record.byHandlerType.entries) {
      HandlerFormats.mergeInto(_byType, entry.key, entry.value);
    }
  }

  /// Folds the kind [change] carries into what is known about the data.
  ///
  /// Allocates nothing for a `(handler type, kind)` pair already seen, which
  /// is what lets the change apply path call it. A full decode would build two
  /// [String]s per change; [OperationEnvelopeCodec.readTypeAndKind] gives the
  /// kind and the bounds of the type instead, and the bytes are compared in
  /// place. Only a pair never seen before pays for the decode, once.
  ///
  /// A change whose envelope cannot be read is skipped.
  void fold(Change change) {
    final payload = change.payloadBytes();

    try {
      final head = OperationEnvelopeCodec.readTypeAndKind(payload);

      for (final folded in _foldedKinds) {
        if (folded.kind == head.kind &&
            folded.type.length == head.typeEnd - head.typeStart &&
            bytesEqualAt(payload, head.typeStart, folded.type)) {
          return;
        }
      }

      final handlerType = UVarint.readString(
        payload,
        offset: 0,
        what: 'handlerType',
      ).value;

      HandlerFormats.mergeInto(
        _byType,
        handlerType,
        HandlerFormats(operationKinds: {head.kind}),
      );
      _foldedKinds.add(
        (
          // `sublist` already copies; a view would pin the whole change.
          type: payload.sublist(head.typeStart, head.typeEnd),
          kind: head.kind,
        ),
      );
    } catch (_) {
      // Ignore changes whose envelope cannot be read: nothing can be said
      // about a payload that cannot even be addressed.
    }
  }

  /// Replaces the known blob versions with the ones [handlers] write.
  ///
  /// Replaced, not added to, which is the one place this tracker forgets
  /// something. A snapshot rewrites the blob of every handler it holds, so the
  /// only versions left in the data are the ones these handlers just wrote.
  /// Keeping an older one — merged in from a peer on another build — would
  /// refuse that peer over a version the document no longer serves.
  ///
  /// Kinds work the other way: a change is immutable, so what the history held
  /// it still needs.
  void replaceBlobVersions(Iterable<Handler<dynamic>> handlers) {
    // `toList` first: writing a key back while iterating the live entries
    // throws `ConcurrentModificationError`.
    for (final entry in _byType.entries.toList()) {
      _byType[entry.key] = HandlerFormats(
        operationKinds: entry.value.operationKinds,
      );
    }
    for (final handler in handlers) {
      // What it *writes*, not the range it reads: this describes the bytes
      // that just went into the snapshot.
      HandlerFormats.mergeInto(
        _byType,
        handler.handlerType,
        HandlerFormats(
          operationKinds: const {},
          blobVersions: BlobVersionRange.single(handler.snapshotBlobVersion),
        ),
      );
    }
  }

  /// What the data asks for, as it stands.
  ///
  /// A type known by its blob version alone is named too, with no kinds. That
  /// is a document restored from a snapshot whose changes were pruned: it holds
  /// a blob, and can still say which version wrote it.
  DocumentRequirements describe() => DocumentRequirements(_byType);
}
