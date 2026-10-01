import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:meta/meta.dart';

/// A snapshot a document just took, and the document it belongs to.
typedef ServerSnapshot = ({String documentId, Snapshot snapshot});

/// Class managing the CRDT document registry on the server.
abstract class CRDTServerRegistry {
  /// Register a document
  Future<void> addDocument(
    String documentId, {
    PeerId? author,
  });

  /// Get a store for an existing document
  Future<CRDTDocument?> getDocument(String documentId);

  /// Check if a document exists
  Future<bool> hasDocument(String documentId);

  /// Remove a document
  Future<void> removeDocument(String documentId);

  /// Get all document IDs
  Future<Set<String>> get documentIds;

  /// Get the number of documents registered
  Future<int> get documentCount;

  /// Create a snapshot of a document
  Future<Snapshot> createSnapshot(String documentId);

  /// Get the latest snapshot of a document
  Future<Snapshot?> getLatestSnapshot(String documentId);

  /// The snapshots the documents of this registry take, once stored.
  ///
  /// Empty by default.
  Stream<ServerSnapshot> get snapshots => const Stream<ServerSnapshot>.empty();

  /// Apply a change to a document.
  ///
  /// Returns `true` if the change was applied, `false` if it was a duplicate
  /// (already known).
  ///
  /// Implementations MUST let [CausallyNotReadyException] propagate when the
  /// change depends on operations the document does not have (and that are not
  /// covered by a snapshot). The server relies on this to detect an
  /// out-of-sync client and trigger a re-sync; swallowing it would silently
  /// drop the change.
  Future<bool> applyChange(String documentId, Change change);

  /// Lets go of everything this registry holds open.
  ///
  /// A registry that writes to disk flushes here, so a server that shuts down
  /// keeps what its clients had already sent. The server calls it once, when
  /// it is disposed.
  ///
  /// The default does nothing, so a registry written before this method
  /// existed keeps working.
  Future<void> close() async {}
}

/// The part of a [CRDTServerRegistry] that does not depend on where the
/// documents are kept.
///
/// Looking a document up, applying a change, snapshotting and counting work
/// the same on any storage.
///
/// Mix it in and give [getDocument]; override [afterSnapshot] when the
/// snapshot has somewhere to go.
mixin CRDTServerRegistryDocuments implements CRDTServerRegistry {
  @override
  Future<int> get documentCount async => (await documentIds).length;

  @override
  Stream<ServerSnapshot> get snapshots => const Stream<ServerSnapshot>.empty();

  /// The document [documentId] holds, or throws [ArgumentError] when this
  /// registry does not serve it.
  @protected
  Future<CRDTDocument> requireDocument(String documentId) async {
    final document = await getDocument(documentId);
    if (document == null) {
      throw ArgumentError.value(documentId, 'documentId', 'no such document');
    }
    return document;
  }

  /// Applies [change] to [documentId] and returns whether it was new.
  ///
  /// [CausallyNotReadyException] propagates, as [CRDTServerRegistry] requires:
  /// the server needs it to tell a client it is out of sync.
  /// [DocumentDisposedException] propagates too — it says the document was let
  /// go under the caller, which is a bug in the caller and not a bad change.
  /// Any other failure gives `false`: one bad change must not take the session
  /// down.
  @override
  Future<bool> applyChange(String documentId, Change change) async {
    final document = await requireDocument(documentId);

    try {
      return document.applyChange(change);
    } on CausallyNotReadyException {
      rethrow;
    } on DocumentDisposedException {
      rethrow;
    } catch (_) {
      return false;
    }
  }

  /// Snapshots [documentId] and hands the snapshot to [afterSnapshot].
  @override
  Future<Snapshot> createSnapshot(String documentId) async {
    final snapshot = (await requireDocument(documentId)).takeSnapshot();
    await afterSnapshot(documentId, snapshot);
    return snapshot;
  }

  /// Runs once [documentId] has snapshotted, before [createSnapshot] returns.
  ///
  /// Where a registry puts the snapshot it just took: on disk, in a map, or
  /// nowhere. The default does nothing.
  @protected
  Future<void> afterSnapshot(String documentId, Snapshot snapshot) async {}
}

/// Reports the snapshots a set of documents take, once started.
///
/// A registry [track]s each document it opens and [untrack]s it when it lets
/// go. Nothing is watched before [start].
class DocumentSnapshotFeed {
  /// Creates a feed that watches nothing yet.
  DocumentSnapshotFeed()
      : _controller = StreamController<ServerSnapshot>.broadcast(),
        _documents = <String, CRDTDocument>{},
        _subscriptions = <String, StreamSubscription<CRDTDocumentEvent>>{},
        _reporting = Future<void>.value();

  FutureOr<void> Function(ServerSnapshot snapshot)? _onSnapshot;

  /// The reports in flight, so the stream gets them in the order taken.
  Future<void> _reporting;

  final StreamController<ServerSnapshot> _controller;

  final Map<String, CRDTDocument> _documents;

  final Map<String, StreamSubscription<CRDTDocumentEvent>> _subscriptions;

  bool _started = false;

  /// Reports the snapshots [document] takes, as [documentId], once started.
  ///
  /// A later call for the same [documentId] replaces this one.
  void track(String documentId, CRDTDocument document) {
    if (_controller.isClosed) {
      return;
    }
    _documents[documentId] = document;
    if (_started) {
      _subscribe(documentId, document);
    }
  }

  /// Stops reporting the snapshots of [documentId].
  Future<void> untrack(String documentId) async {
    _documents.remove(documentId);
    await _subscriptions.remove(documentId)?.cancel();
  }

  /// The snapshots the tracked documents take, once [start] has run.
  Stream<ServerSnapshot> get snapshots => _controller.stream;

  /// Starts watching the tracked documents. Calling it again does nothing.
  ///
  /// [onSnapshot] runs on each snapshot as soon as it is taken. The stream
  /// gets the snapshot once what [onSnapshot] returns completes, and never
  /// when it fails: a registry that stores snapshots waits there for the
  /// storage.
  void start({FutureOr<void> Function(ServerSnapshot snapshot)? onSnapshot}) {
    if (_started) {
      return;
    }
    _started = true;
    _onSnapshot = onSnapshot;
    _documents.forEach(_subscribe);
  }

  /// Stops watching and ends the stream.
  Future<void> close() async {
    _documents.clear();
    final subscriptions = List.of(_subscriptions.values);
    _subscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await _controller.close();
  }

  void _subscribe(String documentId, CRDTDocument document) {
    unawaited(_subscriptions.remove(documentId)?.cancel());
    _subscriptions[documentId] = document.events.listen((event) {
      // A document released during a shutdown can still snapshot while its
      // persistence flushes, after the stream is closed.
      if (event is DocumentSnapshotUpdated &&
          event.reason == SnapshotReason.taken &&
          !_controller.isClosed) {
        _report((documentId: documentId, snapshot: event.snapshot));
      }
    });
  }

  void _report(ServerSnapshot snapshot) {
    final handled = Future<void>.sync(() => _onSnapshot?.call(snapshot)).then(
      (_) => true,
      onError: (Object _) => false,
    );
    _reporting = _reporting.then((_) async {
      if (await handled && !_controller.isClosed) {
        _controller.add(snapshot);
      }
    });
  }
}
