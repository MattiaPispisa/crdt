import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';
import 'package:crdt_socket_sync/src/server_client/server/'
    'persistent_server_registry.dart';

/// The document ids a server serves.
///
/// [CRDTDocumentStorage] holds one document and knows nothing about the
/// others, so the list of documents has to come from somewhere else. A
/// catalog answers three questions: which ids exist, add one, remove one.
/// That is what a [PersistentServerRegistry] needs to answer `hasDocument`,
/// `documentIds` and `documentCount` after a restart.
///
/// It is not a storage. A backend brings its own — a Hive box, a table, a
/// directory listing — and only the three questions below are asked of it.
abstract interface class ServerDocumentCatalog {
  /// Every document id this server knows about.
  Future<Set<String>> get documentIds;

  /// Remembers [documentId].
  ///
  /// Adding the same id twice is not an error.
  Future<void> add(String documentId);

  /// Forgets [documentId].
  ///
  /// Removing an id that is not there is not an error.
  Future<void> remove(String documentId);
}

/// A [ServerDocumentCatalog] that keeps the ids in memory.
///
/// Pass it to [PersistentServerRegistry] for a server that should start
/// empty on every launch. Documents written with it are still on disk after a
/// restart, but the server no longer knows they exist, so it fills up again
/// as clients name their documents.
class InMemoryServerDocumentCatalog implements ServerDocumentCatalog {
  /// Creates a catalog holding [documentIds], empty by default.
  InMemoryServerDocumentCatalog({Set<String>? documentIds})
      : _ids = <String>{...?documentIds};

  final Set<String> _ids;

  @override
  Future<Set<String>> get documentIds async => Set<String>.of(_ids);

  @override
  Future<void> add(String documentId) async {
    _ids.add(documentId);
  }

  @override
  Future<void> remove(String documentId) async {
    _ids.remove(documentId);
  }
}

/// A [ServerDocumentCatalog] that asks the backend.
///
/// The default of [PersistentServerRegistry]. A [CRDTStorageBackend] already
/// lists the documents it holds, so the server keeps no second list that can
/// drift from the first. It survives a restart because the backend does.
///
/// **[remove] deletes.** This catalog is the backend, so forgetting a document
/// here means deleting its changes, its snapshots and its identity — which
/// makes [PersistentServerRegistry.removeDocument] a delete, not a forget. To
/// get a document out of memory and keep it on disk, call
/// [PersistentServerRegistry.releaseDocument] instead.
class BackendDocumentCatalog implements ServerDocumentCatalog {
  /// Creates a catalog over [backend].
  const BackendDocumentCatalog(this.backend);

  /// The backend this catalog reads.
  final CRDTStorageBackend backend;

  @override
  Future<Set<String>> get documentIds async => backend.documentIds;

  @override
  Future<void> add(String documentId) async {
    // A backend lists a document once something of it is stored, and the
    // identity is the smallest thing there is.
    await (await backend.peerIdStorageForDocument(documentId)).loadOrCreate();
  }

  @override
  Future<void> remove(String documentId) async {
    await backend.deleteDocument(documentId);
  }
}
