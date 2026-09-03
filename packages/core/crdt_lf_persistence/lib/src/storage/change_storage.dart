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
abstract interface class CRDTChangeStorage {
  /// The document these changes belong to.
  String get documentId;

  /// Saves [change], replacing one with the same id.
  Future<void> saveChange(Change change);

  /// Saves [changes] in one batch.
  ///
  /// Prefer this to a loop of [saveChange]: a backend that can write a batch
  /// atomically does so here.
  Future<void> saveChanges(List<Change> changes);

  /// Every stored change of this document, in no particular order.
  Future<List<Change>> getChanges();

  /// Deletes [change].
  ///
  /// Returns `true` when it was there, `false` when it was not.
  Future<bool> deleteChange(Change change);

  /// Deletes [changes] in one batch.
  ///
  /// Returns how many were actually there.
  Future<int> deleteChanges(List<Change> changes);

  /// Deletes every change of this document.
  Future<void> clear();

  /// How many changes of this document are stored.
  Future<int> get count;
}
