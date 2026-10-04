import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';
import 'package:crdt_socket_sync/src/common/client/client.dart';
import 'package:crdt_socket_sync/src/common/common/utils.dart';

/// A document on this device: restored from local storage, written back to
/// it, and synced with the other peers.
///
/// It opens and closes its parts in the order that keeps the data: the local
/// copy is restored before the client connects, and the client stops before
/// the last writes are flushed. See the README, "Opening a replica".
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
class CRDTReplica {
  CRDTReplica._({
    required this.document,
    required this.client,
    required this.persistence,
    required CRDTStorageBackend? backend,
    required bool ownsStorage,
  })  : _backend = backend,
        _ownsStorage = ownsStorage;

  /// Opens [documentId] on this device and starts to sync it.
  ///
  /// Completes once the local copy is ready, without waiting for the network.
  /// Follow the connection on [client].
  ///
  /// Leave [storage] `null` to keep the document in memory, and [sync] `null`
  /// to keep it on this device. [onDocument] runs on the new document before
  /// the restore, as on [CRDTStorageBackendDocuments.openDocument].
  ///
  /// [onStorageError] gets every storage error. When the storage fails to open
  /// or to restore, the document starts empty and in memory, and [persistence]
  /// is `null`. [onDocument] then runs a second time, on that document. Without
  /// [onStorageError] that error is rethrown. An error thrown by [onDocument]
  /// is always rethrown.
  ///
  /// [ownsStorage] says whether [close] also closes the backend. When [sync]
  /// throws, what was opened is closed and the error is rethrown.
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

  /// Stops the sync, writes what is still waiting, then closes the document
  /// and the storage.
  ///
  /// Dispose what the app built on [document] first, such as an undo manager.
  /// Calling it twice is safe.
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

    Object? onDocumentError;
    CRDTStorageBackend? backend;
    try {
      backend = await storage();
      final (:document, :persistence) = await backend.openDocument(
        documentId,
        onDocument: onDocument == null
            ? null
            : (document) {
                try {
                  onDocument(document);
                } catch (error) {
                  onDocumentError = error;
                  rethrow;
                }
              },
        onError: onStorageError,
      );
      return (document: document, persistence: persistence, backend: backend);
    } catch (error, stackTrace) {
      if (ownsStorage && backend != null) {
        await tryCatchIgnore(backend.close);
      }
      if (onStorageError == null || identical(error, onDocumentError)) {
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
