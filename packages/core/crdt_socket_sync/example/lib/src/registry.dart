import 'dart:async';

import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:crdt_socket_sync/web_socket_server.dart';
import 'package:en_logger/en_logger.dart';
import 'package:hive/hive.dart';

const _kDocumentsBox = 'documents';

/// Snapshot a document once its log passes this many changes.
const _kCompactAfter = 20;

/// The document ids of this server, kept in a Hive box.
///
/// This is the only piece a persistent server has to write itself:
/// [PersistentServerRegistry] takes care of the documents, but nothing in the
/// storage contract can list them, because a `CRDTDocumentStorage` holds one
/// document and knows nothing about the others.
class HiveDocumentCatalog implements ServerDocumentCatalog {
  HiveDocumentCatalog._(this._box);

  /// Opens the box the ids live in.
  static Future<HiveDocumentCatalog> open() async {
    return HiveDocumentCatalog._(await Hive.openBox<String>(_kDocumentsBox));
  }

  final Box<String> _box;

  @override
  Future<Set<String>> get documentIds async => _box.values.toSet();

  @override
  Future<void> add(String documentId) => _box.put(documentId, documentId);

  @override
  Future<void> remove(String documentId) => _box.delete(documentId);

  /// Closes the box.
  Future<void> close() => _box.close();
}

/// A server-side registry that keeps every document in Hive.
///
/// Everything below the registry — restoring a document on first use, writing
/// the changes that land on it, replacing the snapshot, dropping the history a
/// snapshot covers — is [PersistentServerRegistry]'s job, driven by
/// `CRDTDocument.events`. This function only says *where*.
///
/// Documents are opened lazily, so a server with many documents holds only the
/// ones being edited.
Future<PersistentServerRegistry> openHiveRegistry({
  required HiveDocumentCatalog catalog,
  required EnLogger logger,
}) async {
  CRDTHive.initialize();
  logger.info('Found ${(await catalog.documentIds).length} documents.');

  return PersistentServerRegistry(
    openStorage: CRDTHive.openStorageForDocument,
    // Without this the server writes under a new identity on every restart,
    // and every document's version vector grows an entry that never leaves.
    openPeerIdStorage: CRDTHive.openPeerIdStorageForDocument,
    catalog: catalog,
    compactAfter: _kCompactAfter,
    onError: (error, stack) => logger.error('Storage write failed.\n$error'),
  );
}

/// Tells every client about each snapshot the registry takes.
///
/// A snapshot comes with a prune: the history it covers leaves the server. A
/// client still replaying that history has to be given the snapshot instead,
/// or it asks for changes nobody has any more.
StreamSubscription<ServerSnapshot> broadcastSnapshots({
  required PersistentServerRegistry registry,
  required WebSocketServer server,
  required EnLogger logger,
}) {
  return registry.snapshots.listen((event) async {
    final document = await registry.getDocument(event.documentId);
    if (document == null) {
      return;
    }

    logger.info('Broadcasting snapshot of ${event.documentId}...');
    await server.broadcastMessage(
      SyncMessage.documentStatus(
        documentId: event.documentId,
        snapshot: event.snapshot,
        changes: document.exportChanges(),
        versionVector: document.getVersionVector(),
      ),
    );
  });
}

/// Logs what each document holds, for the demo.
Future<void> showPersistence({
  required PersistentServerRegistry registry,
  required EnLogger logger,
}) async {
  logger.info('Showing persistence state...');
  for (final documentId in await registry.documentIds) {
    final document = await registry.getDocument(documentId);
    final snapshot = await registry.getLatestSnapshot(documentId);

    logger
      ..info('Document: $documentId')
      ..info('  Changes: ${document?.exportChanges().length ?? 0}');
    if (snapshot != null) {
      logger
        ..info('  Latest snapshot:')
        ..info('    VV: ${snapshot.versionVector}')
        ..info('    Data: ${snapshot.data}');
    }
  }
}
