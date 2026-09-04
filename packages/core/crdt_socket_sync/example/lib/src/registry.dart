import 'dart:async';

import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:crdt_socket_sync/web_socket_server.dart';
import 'package:en_logger/en_logger.dart';

/// Snapshot a document once its log passes this many changes.
const _kCompactAfter = 20;

/// Close a document nothing has asked for in this long.
const _kIdleAfter = Duration(minutes: 10);

/// A server-side registry that keeps every document in Hive.
///
/// There is nothing to write here. [PersistentServerRegistry] restores a
/// document on first use, writes the changes that land on it, replaces the
/// snapshot and drops the history a snapshot covers — all driven by
/// `CRDTDocument.events` — and it reads the list of documents from the backend
/// itself. This function only says *where*.
///
/// Documents are opened lazily and released after [_kIdleAfter] without an
/// ask, so a server with many rooms holds only the ones being edited.
Future<PersistentServerRegistry> openHiveRegistry({
  required CRDTHiveBackend backend,
  required EnLogger logger,
}) async {
  logger.info('Found ${(await backend.documentIds).length} documents.');

  return PersistentServerRegistry(
    backend: backend,
    compactAfter: _kCompactAfter,
    idleAfter: _kIdleAfter,
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
