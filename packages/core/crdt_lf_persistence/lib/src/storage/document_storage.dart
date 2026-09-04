import 'dart:async';

import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';

/// Everything one document has on disk: its changes and its snapshots.
///
/// This is what an adapter hands back for a document id, and what
/// [CRDTDocumentPersistence] writes to.
class CRDTDocumentStorage {
  /// Creates the storage of the document [changes] and [snapshots] belong to.
  CRDTDocumentStorage({
    required this.changes,
    required this.snapshots,
  }) : assert(
          changes.documentId == snapshots.documentId,
          'changes and snapshots must belong to the same document',
        );

  /// The document this storage holds.
  String get documentId => changes.documentId;

  /// The stored changes.
  final CRDTChangeStorage changes;

  /// The stored snapshots.
  final CRDTSnapshotStorage snapshots;

  /// Releases what this storage holds open for this document.
  ///
  /// Only what belongs to this document. A backend that shares one connection
  /// between documents keeps it open and closes it itself; a backend that
  /// opens something per document — a box, a file — closes that here.
  ///
  /// The default does nothing. Calling it twice is not an error, and
  /// [CRDTDocumentPersistence.dispose] does not call it: the caller opened the
  /// storage, so the caller closes it.
  FutureOr<void> close() {}

  /// Runs [body] as one unit, so a backend with transactions can make it
  /// all-or-nothing.
  ///
  /// The default just runs it. A backend without transactions is still
  /// correct: it only has a window where half the work is written, and every
  /// step [CRDTDocumentPersistence] takes is safe to repeat.
  ///
  /// [body] must call methods of this storage and await nothing else. A body
  /// that waits on something outside holds the transaction open across it,
  /// and on a backend with one connection that blocks every other document.
  ///
  /// A [body] that returns without suspending must be carried through without
  /// suspending either. On a backend where one connection serves every
  /// document, a suspension here lets another document write inside this
  /// transaction, and a rollback then takes that write with it.
  FutureOr<T> transaction<T>(FutureOr<T> Function() body) => body();
}
