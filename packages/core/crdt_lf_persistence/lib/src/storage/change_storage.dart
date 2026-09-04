import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';

/// The [Change]s of one document, as a backend keeps them.
///
/// Every adapter — Hive, drift, sqlite, a plain file — implements this, so
/// code written against it runs on any of them. A change is identified by its
/// [Change.id]: saving one twice replaces it rather than adding a second copy.
///
/// The store is a plain collection. It does not prune, compact, or know which
/// changes a snapshot covers: that is [CRDTDocumentPersistence]'s job, driven
/// by [CRDTDocument.events].
///
/// Every method returns a [FutureOr]. A backend that answers without touching
/// the disk — sqlite, or a Hive box already in memory — returns the value
/// itself and narrows the return type to say so; an asynchronous backend
/// returns a [Future]. Callers that must work on any adapter use
/// [CRDTFutureOr.chain], which suspends only when there is a future to wait
/// for.
abstract interface class CRDTChangeStorage {
  /// The document these changes belong to.
  String get documentId;

  /// Saves [change], replacing one with the same id.
  FutureOr<void> saveChange(Change change);

  /// Saves [changes] in one batch.
  ///
  /// Prefer this to a loop of [saveChange]: a backend that can write a batch
  /// atomically does so here.
  FutureOr<void> saveChanges(List<Change> changes);

  /// The stored changes of this document, in no particular order.
  ///
  /// Without arguments this is every one of them. [newerThan] keeps only what
  /// the given vector has not seen, which is what restoring on top of a
  /// document already holding state needs. [upTo] keeps only what it has seen,
  /// which rebuilds the document as it was at that version. Together they
  /// describe the range between the two.
  ///
  /// See [filterByVersion], which is the meaning of both bounds and the
  /// fallback for a backend that cannot ask its own query language.
  FutureOr<List<Change>> getChanges({
    VersionVector? newerThan,
    VersionVector? upTo,
  });

  /// Deletes [change].
  ///
  /// Returns `true` when it was there, `false` when it was not.
  FutureOr<bool> deleteChange(Change change);

  /// Deletes [changes] in one batch.
  ///
  /// Returns how many were actually there. A change named twice in one batch
  /// counts once: the answer is how many were deleted, not how many were
  /// asked for.
  FutureOr<int> deleteChanges(List<Change> changes);

  /// Deletes every change of this document.
  FutureOr<void> clear();

  /// How many changes of this document are stored.
  FutureOr<int> get count;
}
