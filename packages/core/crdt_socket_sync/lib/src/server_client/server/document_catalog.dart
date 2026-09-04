import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';
import 'package:crdt_socket_sync/src/server_client/server/persistent_server_registry.dart';

/// The document ids a server serves.
///
/// [CRDTDocumentStorage] holds one document and knows nothing about the
/// others, so the list of documents has to come from somewhere else. This is
/// that somewhere: the smallest thing a [PersistentServerRegistry] needs to
/// answer `hasDocument`, `documentIds` and `documentCount` after a restart.
///
/// It is deliberately not a storage. A backend brings its own — a Hive box, a
/// table, a directory listing — and only the three questions below are asked
/// of it.
///
/// [BackendDocumentCatalog] is the one to reach for: a
/// [CRDTStorageBackend] already knows which documents it holds, so nothing
/// has to be written twice. [InMemoryServerDocumentCatalog] forgets everything
/// when the process ends, and is there for a server that wants exactly that.
abstract interface class ServerDocumentCatalog {
  /// Every document id this server knows about.
  Future<Set<String>> get documentIds;

  /// Remembers [documentId]. Adding one twice is not an error.
  Future<void> add(String documentId);

  /// Forgets [documentId]. Removing one that is not there is not an error.
  Future<void> remove(String documentId);
}

/// A [ServerDocumentCatalog] that keeps the ids in memory.
///
/// The default of [PersistentServerRegistry]. Documents written with it are
/// still on disk after a restart, but the server no longer knows they exist,
/// so it starts empty and fills up as clients name their documents again.
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
/// The default of [PersistentServerRegistry], and the one to use unless there
/// is a reason not to: a [CRDTStorageBackend] already lists the documents it
/// holds, so the server does not keep a second list that can drift from the
/// first. It survives a restart because the backend does.
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
    // identity is the smallest thing there is. It is not a row wasted: it is
    // the one the document goes on to write under.
    await (await backend.peerIdStorageForDocument(documentId)).loadOrCreate();
  }

  @override
  Future<void> remove(String documentId) async {
    await backend.deleteDocument(documentId);
  }
}
