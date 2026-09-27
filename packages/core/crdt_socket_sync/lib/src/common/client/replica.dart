import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';
import 'package:crdt_socket_sync/src/common/client/client.dart';
import 'package:crdt_socket_sync/src/common/common/utils.dart';

/// This device's copy of one document: restored from local storage, written
/// back to it, and kept in sync with the other peers.
///
/// A replica opens and closes its parts in the order they need:
///
/// - the document is restored **before** the client connects. Offline, the
///   local copy is all there is. What was written offline goes out with the
///   first handshake;
/// - the client stops **before** the last writes are flushed, so nothing
///   arrives that the storage would miss. The storage closes last.
///
/// ```dart
/// final replica = await CRDTReplica.open(
///   documentId: 'notes',
///   storage: () => CRDTSqlite.open('notes.db'),
///   sync: (document) => WebSocketClient(
///     url: 'ws://localhost:8080',
///     document: document,
///     author: document.peerId,
///   ),
/// );
/// final text = CRDTFugueTextHandler(replica.document, 'body');
///
/// // ...edit, while the client syncs in the background.
///
/// await replica.close();
/// ```
///
/// Storage and sync are both optional. Without storage the document lives in
/// memory. Without sync it stays on this device.
class CRDTReplica {
  CRDTReplica._({
    required this.document,
    required this.client,
    required this.persistence,
    required CRDTStorageBackend? backend,
    required bool ownsStorage,
  })  : _backend = backend,
        _ownsStorage = ownsStorage;

  /// Opens [documentId] on this device, then starts to sync it.
  ///
  /// In this order:
  ///
  /// 1. [storage] opens the backend, and the document is restored from it
  ///    with [CRDTStorageBackendDocuments.openDocument]. The device writes
  ///    under the [PeerId] it used last time;
  /// 2. [sync] builds the client on the restored document;
  /// 3. the client starts to connect.
  ///
  /// The future completes once the connection has started, before the
  /// handshake ends. So the local copy is ready at once, online or not.
  /// Follow the connection on [CRDTSocketClient.connectionStatus]. A client
  /// that fails to connect retries by its own rules.
  ///
  /// Leave [storage] `null` to keep the document only in memory. Leave [sync]
  /// `null` to keep it on this device.
  ///
  /// [onStorageError] gets every storage error: a backend that fails to open,
  /// a restore that fails, a write that fails later. When the open or the
  /// restore fails, the replica goes on without a local copy: the document
  /// starts empty, in memory, under a new [PeerId], and [persistence] is
  /// `null`. Without [onStorageError], that failure is rethrown instead.
  ///
  /// [onDocument] runs on the new document, before the restore. It is for
  /// what has to be in place first; see
  /// [CRDTStorageBackendDocuments.openDocument]. Handlers do not need it:
  /// build them on [document] after this returns.
  ///
  /// [ownsStorage] says whether [close] closes the backend too. Pass `false`
  /// for a backend that serves other documents as well.
  ///
  /// When [sync] throws, what was already opened is closed and the error is
  /// rethrown.
  static Future<CRDTReplica> open({
    required String documentId,
    FutureOr<CRDTStorageBackend> Function()? storage,
    CRDTSocketClient Function(CRDTDocument document)? sync,
    void Function(CRDTDocument document)? onDocument,
    void Function(Object error, StackTrace stack)? onStorageError,
    bool ownsStorage = true,
  }) async {
    final local = await _openLocal(
      documentId: documentId,
      storage: storage,
      onDocument: onDocument,
      onStorageError: onStorageError,
      ownsStorage: ownsStorage,
    );

    final CRDTSocketClient? client;
    try {
      client = sync?.call(local.document);
    } catch (_) {
      await _release(
        local.document,
        local.persistence,
        local.backend,
        ownsStorage: ownsStorage,
      );
      rethrow;
    }

    final replica = CRDTReplica._(
      document: local.document,
      client: client,
      persistence: local.persistence,
      backend: local.backend,
      ownsStorage: ownsStorage,
    );
    // Not awaited: the local copy is usable now, and a handshake can take as
    // long as the network does.
    if (client != null) {
      unawaited(client.connect());
    }
    return replica;
  }

  /// The document. Build the handlers on it.
  final CRDTDocument document;

  /// The client that syncs [document]; `null` when the replica was opened
  /// without `sync`.
  final CRDTSocketClient? client;

  /// What writes [document] down; `null` without storage, or when the storage
  /// failed to open.
  final CRDTDocumentPersistence? persistence;

  final CRDTStorageBackend? _backend;
  final bool _ownsStorage;
  Future<void>? _closing;

  /// Whether [close] has been called.
  bool get isClosed => _closing != null;

  /// Stops the sync, writes what is still waiting, then releases everything.
  ///
  /// In this order: the client is disposed, [persistence] is flushed and
  /// disposed, [document] is disposed, then the storage is closed. The client
  /// goes first, so no remote change arrives during the flush.
  ///
  /// Dispose what the app built on [document] before this: an undo manager,
  /// a service around a plugin. A second call returns the future of the
  /// first.
  Future<void> close() {
    return _closing ??= _release(
      document,
      persistence,
      _backend,
      client: client,
      ownsStorage: _ownsStorage,
    );
  }

  static Future<_LocalCopy> _openLocal({
    required String documentId,
    required FutureOr<CRDTStorageBackend> Function()? storage,
    required void Function(CRDTDocument document)? onDocument,
    required void Function(Object error, StackTrace stack)? onStorageError,
    required bool ownsStorage,
  }) async {
    if (storage == null) {
      return _inMemory(documentId, onDocument);
    }

    CRDTStorageBackend? backend;
    try {
      backend = await storage();
      final (:document, :persistence) = await backend.openDocument(
        documentId,
        onDocument: onDocument,
        onError: onStorageError,
      );
      return (document: document, persistence: persistence, backend: backend);
    } catch (error, stackTrace) {
      if (ownsStorage && backend != null) {
        await tryCatchIgnore(backend.close);
      }
      if (onStorageError == null) {
        rethrow;
      }
      onStorageError(error, stackTrace);
      return _inMemory(documentId, onDocument);
    }
  }

  static _LocalCopy _inMemory(
    String documentId,
    void Function(CRDTDocument document)? onDocument,
  ) {
    final document = CRDTDocument(documentId: documentId);
    onDocument?.call(document);
    return (document: document, persistence: null, backend: null);
  }

  static Future<void> _release(
    CRDTDocument document,
    CRDTDocumentPersistence? persistence,
    CRDTStorageBackend? backend, {
    required bool ownsStorage,
    CRDTSocketClient? client,
  }) async {
    client?.dispose();
    try {
      await persistence?.dispose();
    } finally {
      document.dispose();
      await persistence?.storage.close();
      if (ownsStorage) {
        await backend?.close();
      }
    }
  }
}

typedef _LocalCopy = ({
  CRDTDocument document,
  CRDTDocumentPersistence? persistence,
  CRDTStorageBackend? backend,
});
