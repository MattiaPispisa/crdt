import 'dart:async';
import 'dart:io';

import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';
import 'package:crdt_socket_sync/web_socket_server.dart';
import 'package:{{name}}_shared/{{name}}_shared.dart';

import 'storage.dart';

/// Snapshot the document once its log passes this many changes.
const _compactAfter = 100;

/// A running sync server and the storage behind it.
///
/// The server holds [documentId], checks every change a client sends and
/// forwards it to the other clients.
class SyncServer {
  SyncServer._({
    required WebSocketServer server,
    required CRDTStorageBackend backend,
    required StreamSubscription<ServerSnapshot> snapshots,
  })  : _server = server,
        _backend = backend,
        _snapshots = snapshots;

  /// Opens the storage in [directory] and starts listening on [host] and
  /// [port].
  ///
  /// The document is created on the first start. A later start with the
  /// same [directory] finds it again, with its history. Pass port `0` to let
  /// the system pick a free port, then read it from [port].
  ///
  /// Throws [StateError] when the server cannot listen, for example because
  /// the port is taken.
  static Future<SyncServer> start({
    required String directory,
    Object? host,
    int port = 8080,
  }) async {
    await Directory(directory).create(recursive: true);
    final backend = await openStorage(directory);
    final registry = PersistentServerRegistry(
      backend: backend,
      compactAfter: _compactAfter,
    );
    await registry.addDocument(documentId);
    openHandlers((await registry.getDocument(documentId))!);

    final server = WebSocketServer(
      serverFactory: () => HttpServer.bind(
        host ?? InternetAddress.anyIPv4,
        port,
      ),
      serverRegistry: registry,
    );
    final snapshots = registry.snapshots.listen(
      (event) => _broadcastSnapshot(server, registry, event),
    );

    if (!await server.start()) {
      await snapshots.cancel();
      await server.dispose();
      await closeStorage(backend);
      throw StateError('The server could not listen on port $port.');
    }

    return SyncServer._(
      server: server,
      backend: backend,
      snapshots: snapshots,
    );
  }

  final WebSocketServer _server;
  final CRDTStorageBackend _backend;
  final StreamSubscription<ServerSnapshot> _snapshots;

  /// The port the server listens on.
  int get port => _server.port;

  /// What the server does: connections, changes, errors.
  Stream<ServerEvent> get events => _server.serverEvents;

  /// Closes every connection, writes what is still waiting and closes the
  /// storage.
  ///
  /// Call it before the process ends, or the last changes can be lost.
  Future<void> stop() async {
    await _snapshots.cancel();
    await _server.dispose();
    await closeStorage(_backend);
  }

  /// Sends the new state of a document to every client after a snapshot.
  ///
  /// A snapshot prunes the history it covers. A client that still asks for
  /// that history gets the snapshot instead.
  static Future<void> _broadcastSnapshot(
    WebSocketServer server,
    PersistentServerRegistry registry,
    ServerSnapshot event,
  ) async {
    final document = await registry.getDocument(event.documentId);
    if (document == null) {
      return;
    }
    await server.broadcastMessage(
      SyncMessage.documentStatus(
        documentId: event.documentId,
        snapshot: event.snapshot,
        changes: document.exportChanges(),
        versionVector: document.getVersionVector(),
      ),
    );
  }
}
