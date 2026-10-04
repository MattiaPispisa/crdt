import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:crdt_socket_sync/web_socket_server.dart';
import 'package:en_logger/en_logger.dart';

/// Snapshot a document once its log passes this many changes.
const _kCompactAfter = 20;

/// Close a document nothing has asked for in this long.
const _kIdleAfter = Duration(minutes: 10);

/// A server-side registry that keeps every document in Hive.
///
/// There is nothing to write here. [PersistentServerRegistry] does the
/// storing on its own, and this function only says *where*.
///
/// Documents are opened lazily and released after [_kIdleAfter] without an
/// ask, so a server with many rooms holds only the ones being edited.
///
/// The caller owns what it gets back: close the registry on shutdown, and
/// [backend] after it.
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
