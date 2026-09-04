import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';
import 'package:crdt_socket_sync/src/server_client/server/document_catalog.dart';
import 'package:crdt_socket_sync/src/server_client/server/registry.dart';

/// A snapshot a document just took, and the document it belongs to.
typedef ServerSnapshot = ({String documentId, Snapshot snapshot});

/// A [CRDTServerRegistry] that keeps every document it serves on disk.
///
/// It holds the live [CRDTDocument]s and routes to them, the way any registry
/// does. What it does **not** do is read and write storage by hand: each
/// document gets a [CRDTDocumentPersistence], which follows
/// [CRDTDocument.events] and writes down what each event reports. So a change
/// applied here is stored, a snapshot replaces the one before it, and a prune
/// drops exactly the changes it covered — all of it batched, and inside a
/// [CRDTDocumentStorage.transaction] where the backend has one.
///
/// It works on any adapter, because it only ever sees the storage contract:
///
/// ```dart
/// final registry = PersistentServerRegistry(
///   backend: await CRDTHive.open(),
///   compactAfter: 500,
/// );
/// ```
///
/// Documents are opened lazily: a document costs nothing until something asks
/// for it. Getting one **out** of memory is the other half, and it does not
/// happen on its own — call [releaseDocument] when a room empties, or pass
/// `idleAfter` and let the registry do it. Without either, a server holds
/// every document it has ever been asked for.
///
/// Call [close] on shutdown. It flushes every open document.
class PersistentServerRegistry implements CRDTServerRegistry {
  /// Creates a registry that stores its documents in [backend].
  ///
  /// [backend] is an adapter's `CRDTHive`, `CRDTDrift` or `CRDTSqlite`. It is
  /// asked for a document's storages the first time that document is needed,
  /// and for the identity the server writes it under — so a restarted server
  /// is the same author it was before, instead of growing every document's
  /// version vector by an entry that never leaves.
  ///
  /// [catalog] is what answers `documentIds`, `hasDocument` and
  /// `documentCount`. It defaults to a [BackendDocumentCatalog] over
  /// [backend], which is what makes the server find its documents again after
  /// a restart. Pass an [InMemoryServerDocumentCatalog] for a server that
  /// should start empty and fill up as clients name their documents.
  ///
  /// [writeDelay] is how long a change waits for the ones after it, so a burst
  /// of edits is one write instead of twenty. It leaves a window where a change
  /// is acknowledged to a client but not yet on disk. That is safe: a client
  /// reconciles at the next handshake and re-sends whatever the server no
  /// longer has. Pass [Duration.zero] to make the window as small as it gets.
  ///
  /// [compactAfter] snapshots and prunes a document once its store holds more
  /// than that many changes. Leave it `null` to keep the whole log.
  ///
  /// [idleAfter] releases a document that nothing has asked for in that long,
  /// the way [releaseDocument] does. Leave it `null` and a document stays open
  /// until [releaseDocument] or [close] is called. See [releaseDocument] for
  /// the one race it has, and why the explicit call does not.
  ///
  /// [onError] is called when a write fails. Without it a failed write is
  /// silent; what it carried stays queued and the next flush tries again. It
  /// also reports a release that failed to write what it was holding.
  PersistentServerRegistry({
    required CRDTStorageBackend backend,
    ServerDocumentCatalog? catalog,
    Duration writeDelay = const Duration(milliseconds: 250),
    int? compactAfter,
    Duration? idleAfter,
    void Function(Object error, StackTrace stack)? onError,
  })  : _backend = backend,
        _catalog = catalog ?? BackendDocumentCatalog(backend),
        _writeDelay = writeDelay,
        _compactAfter = compactAfter,
        _idleAfter = idleAfter,
        _onError = onError;

  final CRDTStorageBackend _backend;
  final ServerDocumentCatalog _catalog;
  final Duration _writeDelay;
  final int? _compactAfter;
  final Duration? _idleAfter;
  final void Function(Object error, StackTrace stack)? _onError;

  /// The countdown to the release of each open document, when `idleAfter` is
  /// set.
  final Map<String, Timer> _idleTimers = <String, Timer>{};

  /// The documents that are open, and the ones being opened.
  ///
  /// The future is stored, not the entry: two callers arriving together share
  /// one open instead of restoring the same document twice.
  final Map<String, Future<_OpenDocument>> _open =
      <String, Future<_OpenDocument>>{};

  final StreamController<ServerSnapshot> _snapshots =
      StreamController<ServerSnapshot>.broadcast();

  /// The snapshot each document takes, as it takes it.
  ///
  /// A server broadcasts the new document status on this, so clients replace
  /// their history instead of replaying a log the server has already pruned.
  /// It carries the snapshots [createSnapshot] takes and the ones
  /// `compactAfter` causes.
  Stream<ServerSnapshot> get snapshots => _snapshots.stream;

  /// The catalog this registry keeps its document ids in.
  ServerDocumentCatalog get catalog => _catalog;

  /// Where this registry keeps its documents.
  CRDTStorageBackend get backend => _backend;

  @override
  Future<void> addDocument(String documentId, {PeerId? author}) async {
    if (await hasDocument(documentId)) {
      return;
    }
    // Opened now rather than on the first read, so a document that was just
    // added is already following its storage when the first change lands —
    // and before the catalog, because a catalog that stores identities would
    // mint one first, and a stored id always beats the [author] handed in.
    await _openDocument(documentId, author: author);
    await _catalog.add(documentId);
  }

  @override
  Future<CRDTDocument?> getDocument(String documentId) async {
    if (!await hasDocument(documentId)) {
      return null;
    }
    return (await _openDocument(documentId)).document;
  }

  @override
  Future<bool> hasDocument(String documentId) async {
    if (_open.containsKey(documentId)) {
      return true;
    }
    return (await _catalog.documentIds).contains(documentId);
  }

  @override
  Future<Set<String>> get documentIds => _catalog.documentIds;

  @override
  Future<int> get documentCount async => (await _catalog.documentIds).length;

  /// Applies [change] to [documentId] and returns whether it was new.
  ///
  /// The write is not here: the [DocumentChangesApplied] this publishes reaches
  /// the document's [CRDTDocumentPersistence], which batches it with whatever
  /// else arrives inside the `writeDelay`.
  ///
  /// [CausallyNotReadyException] propagates, as [CRDTServerRegistry] requires:
  /// the server needs it to tell a client it is out of sync.
  @override
  Future<bool> applyChange(String documentId, Change change) async {
    final document = await getDocument(documentId);
    if (document == null) {
      throw ArgumentError.value(
        documentId,
        'documentId',
        'no such document',
      );
    }

    try {
      return document.applyChange(change);
    } on CausallyNotReadyException {
      rethrow;
    } catch (_) {
      // Any other failure: the change could not be applied.
      return false;
    }
  }

  /// Snapshots [documentId], prunes the history it covers, and waits for both
  /// to reach the disk.
  ///
  /// The waiting is the point: a caller that broadcasts this snapshot has to
  /// know it survives a crash before the clients start replaying against it.
  @override
  Future<Snapshot> createSnapshot(String documentId) async {
    if (!await hasDocument(documentId)) {
      throw ArgumentError.value(documentId, 'documentId', 'no such document');
    }

    final open = await _openDocument(documentId);
    final snapshot = open.document.takeSnapshot();
    await open.persistence.flush();
    return snapshot;
  }

  @override
  Future<Snapshot?> getLatestSnapshot(String documentId) async {
    if (!await hasDocument(documentId)) {
      return null;
    }
    final open = await _openDocument(documentId);
    return open.persistence.storage.snapshots.getLatestSnapshot();
  }

  /// Forgets [documentId]: flushes it, closes it, and drops it from the
  /// catalog.
  ///
  /// **With the default catalog this deletes what the document holds** — see
  /// [BackendDocumentCatalog]. Use [releaseDocument] to get a document out of
  /// memory and keep it on disk.
  @override
  Future<void> removeDocument(String documentId) async {
    await releaseDocument(documentId);
    await _catalog.remove(documentId);
  }

  /// Writes what [documentId] is holding, closes it, and lets go of it.
  ///
  /// The other half of the lazy open. A document stays in memory once it has
  /// been asked for, so a server that never calls this holds every room it has
  /// ever served. Call it when the last client of a room disconnects.
  ///
  /// The id stays in the catalog — the document is still served, it is just
  /// not in memory. That is what separates this from [removeDocument]. The
  /// next [getDocument] reads it back from the storage.
  ///
  /// Nothing here is lost: the persistence flushes before the storage closes.
  ///
  /// One rule: **the document must not be in use.** This disposes it, and a
  /// caller holding the [CRDTDocument] a previous [getDocument] handed back
  /// would be writing into a disposed one. Every session in this package
  /// re-reads through [getDocument], so calling this between two requests is
  /// safe; `idleAfter` takes the same risk on a timer, which is why it should
  /// be far longer than a request takes.
  Future<void> releaseDocument(String documentId) async {
    _idleTimers.remove(documentId)?.cancel();

    final opening = _open.remove(documentId);
    if (opening == null) {
      return;
    }
    await (await opening).dispose();
  }

  /// Flushes and closes every open document.
  ///
  /// The catalog is left as it is: it describes what this server serves, and
  /// that is still true after a shutdown.
  Future<void> close() async {
    for (final timer in _idleTimers.values) {
      timer.cancel();
    }
    _idleTimers.clear();

    final opening = List<Future<_OpenDocument>>.of(_open.values);
    _open.clear();
    for (final open in opening) {
      await (await open).dispose();
    }
    await _snapshots.close();
  }

  /// The open document for [documentId], opening it if this is the first ask.
  Future<_OpenDocument> _openDocument(String documentId, {PeerId? author}) {
    _touch(documentId);

    return _open.putIfAbsent(
      documentId,
      () => _restore(documentId, author).catchError(
        (Object error, StackTrace stack) {
          // A failed open must not be cached: the next caller retries instead
          // of getting the same broken future for as long as the server lives.
          _open.remove(documentId);
          Error.throwWithStackTrace(error, stack);
        },
      ),
    );
  }

  Future<_OpenDocument> _restore(String documentId, PeerId? author) async {
    StreamSubscription<CRDTDocumentEvent>? subscription;

    try {
      final open = await _backend.openDocument(
        documentId,
        author: author,
        // Only the snapshots this document takes. The restore that follows
        // merges the stored one back in, and that is not news anybody is
        // waiting for.
        onDocument: (document) {
          subscription = document.events.listen((event) {
            if (event is DocumentSnapshotUpdated &&
                event.reason == SnapshotReason.taken) {
              _snapshots.add(
                (documentId: documentId, snapshot: event.snapshot),
              );
            }
          });
        },
        writeDelay: _writeDelay,
        compactAfter: _compactAfter,
        onError: _onError,
      );
      return _OpenDocument(open.document, open.persistence, subscription!);
    } catch (_) {
      // The document itself is disposed by [CRDTStorageBackendDocuments
      // .openDocument]; this subscription is the one thing it does not know
      // about.
      await subscription?.cancel();
      rethrow;
    }
  }

  /// Restarts the idle countdown of [documentId], if there is one.
  void _touch(String documentId) {
    final idleAfter = _idleAfter;
    if (idleAfter == null) {
      return;
    }

    _idleTimers.remove(documentId)?.cancel();
    _idleTimers[documentId] = Timer(idleAfter, () async {
      try {
        await releaseDocument(documentId);
      } catch (error, stack) {
        // A release writes before it closes, so it fails for the reason any
        // write fails. Reported where every other write failure is.
        _onError?.call(error, stack);
      }
    });
  }
}

/// A document this registry holds open, and what it holds open with it.
class _OpenDocument {
  _OpenDocument(this.document, this.persistence, this._events);

  final CRDTDocument document;
  final CRDTDocumentPersistence persistence;
  final StreamSubscription<CRDTDocumentEvent> _events;

  /// Writes what is waiting, then lets go of everything.
  ///
  /// The storage is closed here because this registry opened it.
  Future<void> dispose() async {
    await persistence.dispose();
    await _events.cancel();
    await persistence.storage.close();
    document.dispose();
  }
}
