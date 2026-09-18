import 'package:crdt_lf/crdt_lf.dart';
import 'package:meta/meta.dart';

/// Class managing the CRDT document registry on the server.
abstract class CRDTServerRegistry {
  /// Register a document
  Future<void> addDocument(
    String documentId, {
    PeerId? author,
  });

  /// Get a store for an existing document
  Future<CRDTDocument?> getDocument(String documentId);

  /// Check if a document exists
  Future<bool> hasDocument(String documentId);

  /// Remove a document
  Future<void> removeDocument(String documentId);

  /// Get all document IDs
  Future<Set<String>> get documentIds;

  /// Get the number of documents registered
  Future<int> get documentCount;

  /// Create a snapshot of a document
  Future<Snapshot> createSnapshot(String documentId);

  /// Get the latest snapshot of a document
  Future<Snapshot?> getLatestSnapshot(String documentId);

  /// Apply a change to a document.
  ///
  /// Returns `true` if the change was applied, `false` if it was a duplicate
  /// (already known).
  ///
  /// Implementations MUST let [CausallyNotReadyException] propagate when the
  /// change depends on operations the document does not have (and that are not
  /// covered by a snapshot). The server relies on this to detect an
  /// out-of-sync client and trigger a re-sync; swallowing it would silently
  /// drop the change.
  Future<bool> applyChange(String documentId, Change change);

  /// Lets go of everything this registry holds open.
  ///
  /// A registry that writes to disk flushes here, so a server that shuts down
  /// keeps what its clients had already sent. The server calls it once, when
  /// it is disposed.
  ///
  /// The default does nothing, so a registry written before this method
  /// existed keeps working.
  Future<void> close() async {}
}

/// The part of a [CRDTServerRegistry] that does not depend on where the
/// documents are kept.
///
/// A registry differs in how it finds a document and what it does once one has
/// snapshotted. Looking one up, refusing an id it does not serve, and deciding
/// which failures of [applyChange] a client is told about are the same
/// everywhere — and they were written twice before this existed, with two
/// different error messages and no way to keep them in step.
///
/// Mix it in and give [getDocument]; override [afterSnapshot] when the
/// snapshot has somewhere to go.
mixin CRDTServerRegistryDocuments implements CRDTServerRegistry {
  /// The document [documentId] holds, or throws [ArgumentError] when this
  /// registry does not serve it.
  @protected
  Future<CRDTDocument> requireDocument(String documentId) async {
    final document = await getDocument(documentId);
    if (document == null) {
      throw ArgumentError.value(documentId, 'documentId', 'no such document');
    }
    return document;
  }

  /// Applies [change] to [documentId] and returns whether it was new.
  ///
  /// [CausallyNotReadyException] propagates, as [CRDTServerRegistry] requires:
  /// the server needs it to tell a client it is out of sync.
  /// [DocumentDisposedException] propagates too — it says the document was let
  /// go under the caller, which is a bug in the caller and not a bad change.
  /// Any other failure gives `false`: one bad change must not take the session
  /// down.
  @override
  Future<bool> applyChange(String documentId, Change change) async {
    final document = await requireDocument(documentId);

    try {
      return document.applyChange(change);
    } on CausallyNotReadyException {
      rethrow;
    } on DocumentDisposedException {
      rethrow;
    } catch (_) {
      return false;
    }
  }

  /// Snapshots [documentId] and hands the snapshot to [afterSnapshot].
  @override
  Future<Snapshot> createSnapshot(String documentId) async {
    final snapshot = (await requireDocument(documentId)).takeSnapshot();
    await afterSnapshot(documentId, snapshot);
    return snapshot;
  }

  /// Runs once [documentId] has snapshotted, before [createSnapshot] returns.
  ///
  /// Where a registry puts the snapshot it just took: on disk, in a map, or
  /// nowhere. The default does nothing.
  @protected
  Future<void> afterSnapshot(String documentId, Snapshot snapshot) async {}
}
