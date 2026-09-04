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
///   openStorage: CRDTHive.openStorageForDocument,
///   openPeerIdStorage: CRDTHive.openPeerIdStorageForDocument,
///   catalog: myCatalog,
///   compactAfter: 500,
/// );
/// ```
///
/// Documents are opened lazily: a document costs nothing until something asks
/// for it, and a server with ten thousand rooms holds only the live ones.
///
/// Call [close] on shutdown. It flushes every open document.
class PersistentServerRegistry implements CRDTServerRegistry {
  /// Creates a registry that stores its documents through [openStorage].
  ///
  /// [openStorage] is asked once per document, the first time that document is
  /// needed. An adapter's `openStorageForDocument` fits it directly.
  ///
  /// [catalog] is where the document ids live between restarts. Without one
  /// the ids are kept in memory only: the documents stay on disk, but the
  /// server forgets they exist. See [ServerDocumentCatalog].
  ///
  /// [openPeerIdStorage] gives the server a stable identity per document.
  /// Without it a restarted server writes under a new [PeerId] and the
  /// document's version vector gains an entry that never leaves. Pass it
  /// unless the server never authors anything. The `author` of [addDocument]
  /// is then the identity of a document that has none yet, and it is stored.
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
  /// [onError] is called when a write fails. Without it a failed write is
  /// silent; what it carried stays queued and the next flush tries again.
  PersistentServerRegistry({
    required FutureOr<CRDTDocumentStorage> Function(String documentId)
        openStorage,
    ServerDocumentCatalog? catalog,
    FutureOr<CRDTPeerIdStorage> Function(String documentId)? openPeerIdStorage,
    Duration writeDelay = const Duration(milliseconds: 250),
    int? compactAfter,
    void Function(Object error, StackTrace stack)? onError,
  })  : _openStorage = openStorage,
        _openPeerIdStorage = openPeerIdStorage,
        _catalog = catalog ?? InMemoryServerDocumentCatalog(),
        _writeDelay = writeDelay,
        _compactAfter = compactAfter,
        _onError = onError;

  final FutureOr<CRDTDocumentStorage> Function(String documentId) _openStorage;
  final FutureOr<CRDTPeerIdStorage> Function(String documentId)?
      _openPeerIdStorage;
  final ServerDocumentCatalog _catalog;
  final Duration _writeDelay;
  final int? _compactAfter;
  final void Function(Object error, StackTrace stack)? _onError;

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

  @override
  Future<void> addDocument(String documentId, {PeerId? author}) async {
    if (await hasDocument(documentId)) {
      return;
    }
    await _catalog.add(documentId);
    // Opened now rather than on the first read, so a document that was just
    // added is already following its storage when the first change lands.
    await _openDocument(documentId, author: author);
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
  /// What the backend holds is left alone. Deleting rows is the adapter's job,
  /// and a caller that wants the bytes gone calls the adapter after this.
  @override
  Future<void> removeDocument(String documentId) async {
    final opening = _open.remove(documentId);
    if (opening != null) {
      final open = await opening;
      await open.dispose();
    }
    await _catalog.remove(documentId);
  }

  /// Flushes and closes every open document.
  ///
  /// The catalog is left as it is: it describes what this server serves, and
  /// that is still true after a shutdown.
  Future<void> close() async {
    final opening = List<Future<_OpenDocument>>.of(_open.values);
    _open.clear();
    for (final open in opening) {
      await (await open).dispose();
    }
    await _snapshots.close();
  }

  /// The open document for [documentId], opening it if this is the first ask.
  Future<_OpenDocument> _openDocument(String documentId, {PeerId? author}) {
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
    final peerId = await _peerIdFor(documentId, author);
    final document = CRDTDocument(documentId: documentId, peerId: peerId);

    // Only the snapshots this document takes. The restore below merges the
    // stored one back in, and that is not news anybody is waiting for.
    final subscription = document.events.listen((event) {
      if (event is DocumentSnapshotUpdated &&
          event.reason == SnapshotReason.taken) {
        _snapshots.add((documentId: documentId, snapshot: event.snapshot));
      }
    });

    try {
      final persistence = await CRDTDocumentPersistence.open(
        document,
        await _openStorage(documentId),
        writeDelay: _writeDelay,
        compactAfter: _compactAfter,
        onError: _onError,
      );
      return _OpenDocument(document, persistence, subscription);
    } catch (_) {
      await subscription.cancel();
      document.dispose();
      rethrow;
    }
  }

  /// The identity [documentId] is written under.
  ///
  /// A stored id wins over [author]: it is what the document already wrote
  /// under, and writing under a second one would make this server look like
  /// two peers. [author] is the seed for a document that has none yet, and it
  /// is stored, so the next restart finds it.
  Future<PeerId> _peerIdFor(String documentId, PeerId? author) async {
    final open = _openPeerIdStorage;
    if (open == null) {
      return author ?? PeerId.generate();
    }

    final storage = await open(documentId);
    if (author == null) {
      return storage.loadOrCreate();
    }

    final stored = await storage.getPeerId();
    if (stored != null) {
      return stored;
    }
    await storage.savePeerId(author);
    return author;
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
