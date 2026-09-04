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
/// The default is [InMemoryServerDocumentCatalog], which forgets everything
/// when the process ends. A server that wants its documents back after a
/// restart writes one that does not.
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
