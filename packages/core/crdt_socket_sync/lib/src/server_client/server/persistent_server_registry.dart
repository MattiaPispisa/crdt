import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';
import 'package:crdt_socket_sync/src/server_client/server/'
    'document_catalog.dart';
import 'package:crdt_socket_sync/src/server_client/server/registry.dart';

/// A [CRDTServerRegistry] that keeps every document it serves on disk.
///
/// It holds the live [CRDTDocument]s and routes to them, the way any registry
/// does. It never reads or writes storage by hand. Each document gets a
/// [CRDTDocumentPersistence], which follows [CRDTDocument.events] and writes
/// down what each event reports. So a change applied here is stored, a
/// snapshot replaces the one before it, and a prune drops exactly the changes
/// it covered — all of it batched, and inside a
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
/// for it. Getting one back **out** of memory never happens on its own. Call
/// [releaseDocument] when a room empties, or pass `idleAfter` and let the
/// registry do it. With neither, a server holds every document it has ever
/// been asked for.
///
/// Call [close] on shutdown. It flushes every open document.
class PersistentServerRegistry
    with CRDTServerRegistryDocuments
    implements CRDTServerRegistry {
  /// Creates a registry that stores its documents in [backend].
  ///
  /// [backend] is what an adapter opens: `CRDTHive.open()`, `CRDTDrift.open()`
  /// or `CRDTSqlite.open()`. It is asked for a document's storages the first
  /// time that document is needed,
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
  /// [keepSnapshots] is how many snapshots each document keeps on the disk, as
  /// on `CRDTDocumentPersistence.open`.
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
    int? keepSnapshots = 1,
    Duration? idleAfter,
    void Function(Object error, StackTrace stack)? onError,
  })  : _backend = backend,
        _catalog = catalog ?? BackendDocumentCatalog(backend),
        _writeDelay = writeDelay,
        _compactAfter = compactAfter,
        _keepSnapshots = keepSnapshots,
        _idleAfter = idleAfter,
        _onError = onError,
        _feed = DocumentSnapshotFeed() {
    _startSnapshots();
  }

  final CRDTStorageBackend _backend;
  final ServerDocumentCatalog _catalog;
  final Duration _writeDelay;
  final int? _compactAfter;
  final int? _keepSnapshots;
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

  /// [close] has run, so nothing must be opened again.
  bool _closed = false;

  /// The releases still running, by document id.
  ///
  /// A release writes before it closes, so it takes as long as a write takes.
  /// An open of the same document arriving in that window has to wait for it:
  /// the storage is about to be closed, and a backend hands the same storage
  /// back for the same document.
  final Map<String, Future<void>> _releasing = <String, Future<void>>{};

  /// The documents [_releasing] is letting go of.
  final Map<String, Future<_OpenDocument>> _released =
      <String, Future<_OpenDocument>>{};

  final DocumentSnapshotFeed _feed;

  @override
  Stream<ServerSnapshot> get snapshots => _feed.snapshots;

  void _startSnapshots() => _feed.start(onSnapshot: _waitForStored);

  /// Waits until the storage of the document can bring back the version of
  /// [taken]. Throws when the document closes first.
  ///
  /// It reads [_open] and [_released] and never [_openDocument]: a snapshot
  /// taken while a document is released must not open it again.
  Future<void> _waitForStored(ServerSnapshot taken) async {
    final opening = _open[taken.documentId] ?? _released[taken.documentId];
    if (opening == null) {
      throw StateError('${taken.documentId} is not open');
    }
    await (await opening).persistence.whenStored(taken.snapshot.versionVector);
  }

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
    // mint one first, and a stored id always beats the `author` handed in.
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

  /// Waits for the snapshot and the prune it caused to reach the disk.
  ///
  /// The waiting is the point: a caller that broadcasts this snapshot has to
  /// know it survives a crash before the clients start replaying against it.
  /// Throws when either write fails.
  @override
  Future<void> afterSnapshot(String documentId, Snapshot snapshot) async {
    await (await _openDocument(documentId))
        .persistence
        .flush(throwOnError: true);
  }

  /// The newest snapshot stored for [documentId].
  ///
  /// `null` when this registry does not serve [documentId], and `null` when it
  /// serves it but no snapshot has been stored yet.
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
  Future<void> releaseDocument(String documentId) {
    _idleTimers.remove(documentId)?.cancel();

    final opening = _open.remove(documentId);
    if (opening == null) {
      // Nothing open, but a release may still be running: join it rather than
      // reporting a document as let go while its last write is in flight.
      return _releasing[documentId] ?? Future<void>.value();
    }

    _released[documentId] = opening;
    final releasing = _release(documentId, opening);
    _releasing[documentId] = releasing;
    return releasing;
  }

  Future<void> _release(
    String documentId,
    Future<_OpenDocument> opening,
  ) async {
    try {
      await (await opening).dispose();
    } finally {
      await _feed.untrack(documentId);
      // `removeWhere`, not `remove`: the value is a future, and dropping it
      // by name reads as an unawaited one.
      _releasing.removeWhere((id, _) => id == documentId);
      _released.removeWhere((id, _) => id == documentId);
    }
  }

  /// Flushes and closes every open document.
  ///
  /// The catalog is left as it is: it describes what this server serves, and
  /// that is still true after a shutdown.
  ///
  /// Asking this registry for a document afterwards throws a [StateError].
  @override
  Future<void> close() async {
    _closed = true;
    for (final timer in _idleTimers.values) {
      timer.cancel();
    }
    _idleTimers.clear();

    // A loop, not one pass: an open started before `_closed` was set is still
    // in flight, and it installs its entry when it lands. A single pass over
    // the map would leave that document writing for the life of the process.
    while (_open.isNotEmpty || _releasing.isNotEmpty) {
      final releasing = List<Future<void>>.of(_releasing.values);
      final opening = List<Future<_OpenDocument>>.of(_open.values);
      _open.clear();

      for (final release in releasing) {
        try {
          await release;
        } catch (error, stack) {
          _onError?.call(error, stack);
        }
      }
      for (final open in opening) {
        try {
          await (await open).dispose();
        } catch (error, stack) {
          // One document that cannot be written must not keep the others open.
          _onError?.call(error, stack);
        }
      }
    }

    await _feed.close();
  }

  /// The open document for [documentId], opening it if this is the first ask.
  Future<_OpenDocument> _openDocument(String documentId, {PeerId? author}) {
    // The one place every open goes through, so one check covers them all.
    if (_closed) {
      throw StateError(
        'this registry is closed, so $documentId cannot be opened',
      );
    }

    // A release of this document is still writing. Opening now would hand back
    // the very document it is about to dispose, so wait and open a fresh one.
    final releasing = _releasing[documentId];
    if (releasing != null) {
      return releasing.then((_) => _openDocument(documentId, author: author));
    }

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
    try {
      final open = await _backend.openDocument(
        documentId,
        author: author,
        onDocument: (document) => _feed.track(documentId, document),
        writeDelay: _writeDelay,
        compactAfter: _compactAfter,
        keepSnapshots: _keepSnapshots,
        onError: _onError,
      );
      return _OpenDocument(open.document, open.persistence);
    } catch (_) {
      await _feed.untrack(documentId);
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
  _OpenDocument(this.document, this.persistence);

  final CRDTDocument document;
  final CRDTDocumentPersistence persistence;

  /// Writes what is waiting, then lets go of everything.
  ///
  /// The storage is closed here because this registry opened it.
  Future<void> dispose() async {
    await persistence.dispose();
    await persistence.storage.close();
    document.dispose();
  }
}
