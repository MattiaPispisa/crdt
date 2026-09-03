import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/compound/compound.dart';
import 'package:crdt_lf/src/devtools/devtools.dart' as devtools;
import 'package:crdt_lf/src/snapshot/blob_version.dart';
import 'package:crdt_lf/src/transaction/transaction_manager.dart';
import 'package:crdt_lf/src/utils/bytes.dart';
import 'package:crdt_lf/src/utils/uuid.dart';
import 'package:hlc_dart/hlc_dart.dart';

// [Handler] shares this library so the hooks the framework calls on it can stay
// private. See the "Extension points" section of its documentation for the
// members a custom handler is meant to override.
part '../handler/handler.dart';

// The mixins a consumer of the document is built from, and the read-only
// document a [HistorySession] walks through.
part 'providers.dart';
part 'delta_provider.dart';
part 'history.dart';

// Undo, which is written as new inverse operations rather than as a removal.
part 'undo_manager.dart';

/// Defines the foundational contract for a CRDT document.
///
/// This abstract class serves as the common interfaces between
/// the live [CRDTDocument] and the static read-only document.
abstract class BaseCRDTDocument {
  bool _isDisposed = false;

  /// Delta events that have been published but not handed out yet;
  /// [_flushDeltaEvents] hands them out.
  ///
  /// One of three parts that decide when a change reaches a watcher. The outbox
  /// moves delivery from the middle of the work to its end, so no listener runs
  /// on a half-applied document; the synchronous controller in
  /// [DeltaProvider.watch] makes that end immediate rather than a microtask
  /// later; and [TransactionManager]'s `onFlushed` is the moment the document
  /// holds nothing, the only point safe for code that may write back.
  List<void Function()>? _deltaOutbox;

  /// Whether [_flushDeltaEvents] is already handing events out.
  bool _flushingDeltas = false;

  /// Who asked for the work running right now, stamped onto the delta events it
  /// produces; `null` outside any call that named one.
  ///
  /// A document that takes no operation never has one.
  Object? get _deltaOrigin => null;

  /// Holds one event until the document is settled.
  ///
  /// The microtask covers the paths that end nowhere near a transaction — a
  /// cache dropped by hand, say. On a normal path the commit flushes first and
  /// the microtask finds nothing.
  void _enqueueDeltaEvent(void Function() deliver) {
    final outbox = _deltaOutbox;
    if (outbox != null) {
      outbox.add(deliver);
      return;
    }
    _deltaOutbox = <void Function()>[deliver];
    scheduleMicrotask(_flushDeltaEvents);
  }

  /// Hands out every event waiting in the outbox.
  ///
  /// A listener may write back, publishing more events; the loop picks those up
  /// so its work reaches everyone in this same pass, after it returns. A nested
  /// call does nothing: the loop it would duplicate is already running.
  void _flushDeltaEvents() {
    if (_flushingDeltas) {
      return;
    }
    _flushingDeltas = true;
    try {
      while (true) {
        final outbox = _deltaOutbox;
        if (outbox == null) {
          return;
        }
        _deltaOutbox = null;
        for (final deliver in outbox) {
          deliver();
        }
      }
    } finally {
      _flushingDeltas = false;
    }
  }

  /// Whether the document is disposed
  bool get isDisposed => _isDisposed;

  /// Gets the current timestamp of this document
  HybridLogicalClock get hlc;

  /// Gets the peer ID of this document
  PeerId get peerId;

  /// Gets the document ID of this document
  String get documentId;

  /// Gets the current version of this document (the frontiers of the DAG)
  Set<OperationId> get version;

  /// Registers an [Operation] to this document.
  ///
  /// If there isn't a transaction an implicit transaction is opened
  ///
  /// Else the operation is added to the current transaction.
  void registerOperation(Operation operation);

  /// Exports [Change]s from a specific version.
  ///
  /// If [fromVersionVector] is provided, it is used to filter the changes.
  /// Only changes that are newer than the given
  /// [fromVersionVector] are returned.
  ///
  /// If [from] is provided, it is used to filter the changes.
  /// Only changes that are not ancestors of the given [from] are returned.
  ///
  /// If neither [fromVersionVector] nor [from] are provided,
  /// all changes are returned.
  List<Change> exportChanges({
    Set<OperationId>? from,
    VersionVector? fromVersionVector,
  });

  /// Returns the [Change]s produced by the handler with the given [handlerId].
  ///
  /// If [fromVersionVector] is provided, only changes strictly newer than it
  /// (per author) are returned.
  List<Change> changesForHandler(
    String handlerId, {
    VersionVector? fromVersionVector,
  });

  /// Returns the number of [Change]s produced by the handler with the given
  /// [handlerId].
  int changeCountForHandler(String handlerId);

  /// A monotonically increasing revision for the handler with the given
  /// [handlerId].
  ///
  /// It increases (at least once per [CRDTDocument.updates] event) every time
  /// the observable state of the handler **may have changed**:
  /// changes targeting it are applied (local or imported),
  /// or a snapshot carrying its state is imported/merged.
  ///
  /// **It never decreases** — in particular, history pruning
  /// does not affect it — so two equal readings guarantee the handler state
  /// did not change in between. **This is the signal reactive bindings should
  /// watch.**
  int revisionForHandler(String handlerId);

  /// Prepares the system to perform a mutation.
  void prepareMutation();

  /// The last snapshot of this document
  Snapshot? get _lastSnapshot;

  /// The registered snapshot providers
  Map<String, Handler<dynamic>> get _handlers;

  /// Register a [SnapshotProvider]
  void registerHandler(Handler<dynamic> handler) {
    _ensureNotDisposed('registerHandler');

    if (_handlers.containsKey(handler.id)) {
      throw HandlerAlreadyRegisteredException(
        'Handler with ID ${handler.id} already registered',
      );
    }
    _handlers[handler.id] = handler;
    handler._document = this;
  }

  /// Factories used to lazily reconstruct handlers from their type string.
  ///
  /// A factory is never inserted directly: when it is called, the handler it
  /// builds self-registers into [_handlers] through this chain:
  ///
  /// ```md
  /// factory(this, id)
  /// → new CRDTMapRefHandler(doc, id)
  ///   → super Handler(doc)
  ///     → doc.registerHandler(this)
  ///       → _handlers[id] = this
  /// ```
  final Map<String, HandlerFactory> _factories = {};

  /// Registers a [HandlerFactory] for handlers whose [Handler.handlerType]
  /// equals [type]. Registering the same [type] twice overwrites the factory.
  void registerFactory(String type, HandlerFactory factory) {
    _factories[type] = factory;
  }

  /// Resolves [ref] to a handler instance.
  ///
  /// Returns the already-registered handler with `ref.id`, or instantiates it
  /// via the registered [HandlerFactory] for `ref.type` (the constructor
  /// self-registers it). Returns `null` when no factory is registered.
  Handler<dynamic>? resolveHandler(HandlerRef ref) {
    final existing = _handlers[ref.id];
    if (existing != null) {
      return existing;
    }
    final factory = _factories[ref.type];
    if (factory == null) {
      return null;
    }
    return factory(this, ref.id);
  }

  /// If [_isDisposed] is `true`, throws [DocumentDisposedException]
  /// with the given [methodInvoke].
  void _ensureNotDisposed(String methodInvoke) {
    if (_isDisposed) {
      throw DocumentDisposedException(methodInvoke);
    }
  }

  /// Disposes of the document
  void dispose() {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;
    // Before the registry is emptied: a watcher of any document, live or
    // static, is told the stream ends here rather than waiting on one that can
    // never fire again.
    for (final handler in _handlers.values) {
      handler._closeDeltas();
    }
    _handlers.clear();
  }
}

/// CRDT Document implementation
///
/// A CRDTDocument is the main entry point for the CRDT system.
/// It manages the DAG, ChangeStore, and provides methods for creating,
/// applying, exporting, and importing changes.
///
/// Identity:
/// - `documentId`: identifies the document/resource. It is useful for routing,
///   persistence, and access control. It does not participate in operation
///   identifiers.
/// - `peerId`: identifies the peer/author generating operations. It is used in
///   `OperationId` together with the Hybrid Logical Clock.
///
/// {@template document_example}
/// ## Example
/// ```dart
/// // Create two documents (simulating different peers)
///  final doc1 = CRDTDocument(
///    peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
///  );
///  final doc2 = CRDTDocument(
///    peerId: PeerId.parse('a90dfced-cbf0-4a49-9c64-f5b7b62fdc18'),
///  );
///
///  // Create text handlers
///  final fugueTextDoc1 = CRDTFugueTextHandler(doc1, 'text');
///  final fugueTextDoc2 = CRDTFugueTextHandler(doc2, 'text');
///
///  // Initial state
///  fugueTextDoc1.insert(0, 'Hello');
///
///  // Sync doc1 to doc2
///  var changesDoc1 = doc1.exportChanges();
///  doc2.importChanges(changesDoc1);
///
///  // Concurrent edits
///  fugueTextDoc1.insert(5, ' World'); // doc1: "Hello World"
///  fugueTextDoc2.insert(5, ' Dart'); // doc2: "Hello Dart"
///
///  // Sync both ways
///  final changes1After = doc1.exportChanges();
///  final changes2After = doc2.exportChanges();
///
///  doc2.importChanges(changes1After);
///  doc1.importChanges(changes2After);
///
///  // Both documents will have the same final state
///  print(fugueTextDoc1.value); // Prints "Hello World Dart" or "Hello Dart World"
///  print(fugueTextDoc2.value); // Prints the same as text1
///
///  // Create list handler
///  final list1 = CRDTListHandler(doc1, 'list');
///  final list2 = CRDTListHandler(doc2, 'list');
///
///  list1
///    ..insert(0, 'Hello')
///    ..insert(1, 'World')
///    ..insert(2, 'Dart');
///
///  print(list1.value); // Prints ["Hello", "World", "Dart"]
///
///  // sync doc1 to doc2
///  changesDoc1 = doc1.exportChanges();
///  doc2.importChanges(changesDoc1);
///
///  print(list2.value); // Prints ["Hello", "World", "Dart"]
///
///  // history session
///  final historySession = doc1.toTimeTravel();
///  final viewListHandler =
///      historySession.getHandler(
///    (doc) => CRDTListHandler(doc, 'list'),
///  );
///  print(viewListHandler.value); // Prints ["Hello", "World", "Dart"]
///
///  historySession.previous();
///  print(viewListHandler.value); // Prints ["Hello", "World"]
///
///  // transaction
///  doc1.runInTransaction(() {
///    list1
///      ..insert(3, 'Flutter')
///      ..insert(4, '!');
///  });
///  // insertions are committed at the end
///  print(list1.value); // Prints ["Hello", "World", "Dart", "Flutter", "!"]
///
///  // snapshot
///  // save pruning
///  var snapshotDoc1 = doc1.takeSnapshot(pruneHistory: false);
///  changesDoc1 = doc1.exportChanges();
///  doc2.import(
///    snapshot: snapshotDoc1,
///    changes: changesDoc1,
///    pruneHistory: false,
///  );
///
///  // changes are read starting from the snapshot then changed are applied
///  print(list2.value); // Prints ["Hello", "World", "Dart", "Flutter", "!"]
///  // changes are not pruned
///  print(doc1.exportChanges().length); // Prints 8
///
///  // aggressive pruning
///  snapshotDoc1 = doc1.takeSnapshot(
///    pruneHistory: true,
///  );
///  // changes are pruned
///  doc1.garbageCollect(doc1.getVersionVector());
///  print(doc1.exportChanges().length); // Prints 0
/// ```
/// {@endtemplate}
class CRDTDocument extends BaseCRDTDocument {
  /// Creates a new [CRDTDocument] with the given identifiers.
  ///
  /// - [peerId]: the identifier of the local peer (author of operations).
  ///   If not provided, a new one is generated.
  /// - [documentId]: the identifier of the document. If not provided, a new
  ///   random identifier is generated.
  /// - [initialClock]: the initial hybrid logical clock for this document.
  ///   If not provided, defaults to [HybridLogicalClock.initialize] (clock
  ///   starting at zero). Use [HybridLogicalClock.now] to start from the
  ///   current physical time.
  ///
  /// {@macro document_example}
  CRDTDocument({
    PeerId? peerId,
    String? documentId,
    HybridLogicalClock? initialClock,
  })  : _dag = DAG.empty(),
        _changeStore = ChangeStore.empty(),
        _peerId = peerId ?? PeerId.generate(),
        _documentId = documentId ?? generateUuid(),
        _clock = initialClock ?? HybridLogicalClock.initialize(),
        _eventsController = StreamController<CRDTDocumentEvent>.broadcast(),
        _updatesController = StreamController<void>.broadcast(),
        _handlers = {} {
    _transactionManager = TransactionManager(
      flushWork: _transactionFlushWork,
      onFlushed: _onTransactionFlushed,
    );
    devtools.handleCreated(this);
  }

  /// The DAG that tracks causal relationships between operations
  final DAG _dag;

  /// The store for changes
  final ChangeStore _changeStore;

  /// The ID of the peer that owns this document
  final PeerId _peerId;

  /// The ID of the document/resource
  final String _documentId;

  /// The hybrid logical clock for this document
  final HybridLogicalClock _clock;

  /// Per-handler monotonic revisions. See [revisionForHandler].
  final Map<String, int> _handlerRevisions = {};

  @override
  Object? _deltaOrigin;

  /// Runs [body] with [origin] on the delta events it produces.
  ///
  /// Set for the whole call, not the apply alone: a local delta is collected
  /// while the operation runs and published at the commit that ends it.
  ///
  /// A nested call that names none keeps the outer origin. Restoring rather
  /// than clearing lets a listener write back from inside a flush without
  /// taking the origin of the work it interrupted.
  T _withDeltaOrigin<T>(Object? origin, T Function() body) {
    final previous = _deltaOrigin;
    _deltaOrigin = origin ?? previous;
    try {
      return body();
    } finally {
      _deltaOrigin = previous;
    }
  }

  /// The [CRDTUndoManager]s recording this document, or `null` when there is
  /// none.
  ///
  /// Null and not an empty list so that a document nobody undoes pays one
  /// comparison per local write.
  List<CRDTUndoManager>? _undoManagers;

  void _registerUndoManager(CRDTUndoManager manager) {
    (_undoManagers ??= <CRDTUndoManager>[]).add(manager);
  }

  void _unregisterUndoManager(CRDTUndoManager manager) {
    final managers = _undoManagers;
    if (managers == null) {
      return;
    }
    managers.removeWhere((m) => identical(m, manager));
    if (managers.isEmpty) {
      _undoManagers = null;
    }
  }

  /// Offers [operation] to every manager, before [handler] folds it in.
  void _captureForUndo(Handler<dynamic> handler, Operation operation) {
    final managers = _undoManagers;
    if (managers == null) {
      return;
    }
    for (final manager in managers) {
      manager._capture(handler, operation);
    }
  }

  /// Closes the undo steps a committed transaction filled, then hands out the
  /// delta events it produced.
  ///
  /// In that order: a listener reacting to a delta reads a settled
  /// [CRDTUndoManager.canUndo].
  void _onTransactionFlushed() {
    final managers = _undoManagers;
    if (managers != null) {
      for (final manager in managers) {
        manager._closeEntry();
      }
    }
    _flushDeltaEvents();
  }

  @override
  PeerId get peerId => _peerId;

  @override
  String get documentId => _documentId;

  @override
  HybridLogicalClock get hlc => _clock.copy();

  @override
  Snapshot? _lastSnapshot;

  @override
  final Map<String, Handler<dynamic>> _handlers;

  /// Updates the document's clock to the current physical time.
  void _tickClock({int? physicalTime}) {
    final pt = physicalTime ?? DateTime.now().millisecondsSinceEpoch;
    _clock.localEvent(pt);
  }

  /// Moves the document's clock forward, as registering an operation would.
  ///
  /// Spends a clock value without producing an operation. Use it to bring two
  /// documents' clocks level, so they write in the same tick on purpose. It is
  /// not a way to keep time.
  @override
  void prepareMutation() {
    _ensureNotDisposed('prepareMutation');
    _tickClock();
  }

  @override
  Set<OperationId> get version {
    return _dag.frontiers;
  }

  /// All handlers currently registered on this document, keyed by their id.
  ///
  /// Intended for read-only introspection (devtools, debugging). Do not mutate.
  Map<String, Handler<dynamic>> get registeredHandlers =>
      Map.unmodifiable(_handlers);

  /// Generates a globally-unique id for a handler created dynamically.
  ///
  /// The id is a random UUID (not a [PeerId]: it identifies a handler, not a
  /// peer). It is generated by the creator and carried inside the [HandlerRef],
  /// so remote peers reuse the same id verbatim when reconstructing the tree.
  String newHandlerId() => generateUuid();

  /// Reconstructs every handler reachable from the data currently held by this
  /// document (changes and snapshot), using the registered factories.
  ///
  /// A peer that received only the [Change]s (or a [Snapshot]) and registered
  /// the relevant factories can call this to rebuild the full handler tree
  /// without knowing the document structure in advance. Reading lazily from a
  /// known root via `getRef`/`resolved` also works without calling this.
  void reconstruct() {
    _ensureNotDisposed('reconstruct');

    final discovered = <String, String>{};
    for (final change in exportChanges()) {
      try {
        final env = OperationEnvelopeCodec.decode(change.payloadBytes());
        discovered[env.handlerId] = env.handlerType;
      } catch (_) {
        // Ignore changes whose envelope cannot be decoded.
      }
    }
    discovered.addAll(_snapshotManifest());

    for (final entry in discovered.entries) {
      if (!_handlers.containsKey(entry.key)) {
        _factories[entry.value]?.call(this, entry.key);
      }
    }

    _materializeReachable();
  }

  /// The handlers that are not referenced by any other container handler,
  /// i.e. the entry points of the nested tree.
  Iterable<Handler<dynamic>> roots() {
    final referenced = <String>{};
    for (final handler in _handlers.values) {
      if (handler is ContainerHandler) {
        for (final ref in (handler as ContainerHandler).childRefs()) {
          referenced.add(ref.id);
        }
      }
    }
    return _handlers.values
        .where((handler) => !referenced.contains(handler.id))
        .toList();
  }

  /// Instantiates every handler reachable from the currently registered
  /// container handlers by following their references to a fixed point.
  ///
  /// Handlers inside refs are created lazily.
  /// This means that functions using [_handlers] cannot find the lazy ones
  /// that have not yet been instantiated
  /// (e.g., handlers left unexplored during a snapshot will not be saved).
  /// This method ensures that every reachable handler is instantiated.
  void _materializeReachable() {
    // Performs a Breadth-First Search (BFS) starting from the known handlers.
    final queue = Queue<Handler<dynamic>>.of(_handlers.values);
    final seen = <String>{};
    while (queue.isNotEmpty) {
      final handler = queue.removeFirst();
      if (!seen.add(handler.id)) {
        continue;
      }
      if (handler is ContainerHandler) {
        for (final ref in (handler as ContainerHandler).childRefs()) {
          final child = resolveHandler(ref);
          if (child != null && !seen.contains(child.id)) {
            queue.add(child);
          }
        }
      }
    }
  }

  /// Reads the `{id: type}` manifest persisted in the last snapshot, or an
  /// empty map if there is no snapshot or it predates the manifest.
  Map<String, String> _snapshotManifest() {
    final snapshot = _lastSnapshot;
    if (snapshot == null) {
      return const {};
    }
    final blob = snapshot.data[_handlerManifestKey];
    if (blob == null) {
      return const {};
    }
    return _decodeHandlerManifest(blob);
  }

  /// A stream controller for the moves of the durable state.
  final StreamController<CRDTDocumentEvent> _eventsController;

  /// A stream of the moves of this document's durable state: the changes it
  /// holds, and the snapshot they are replayed on top of.
  ///
  /// This is what a consumer mirroring the document follows — a persistence
  /// adapter, a log. It reports every change that enters the store, wherever it
  /// came from, so the mirror stays current without ever calling
  /// [exportChanges] again.
  ///
  /// It is **not** the signal a view rebuilds on: it says what was written
  /// down, not what the state now reads as. Use [revisionForHandler] or
  /// `Handler.watch()` for that.
  ///
  /// Events are handed out once the document is settled, in the order the
  /// moves happened.
  ///
  /// ```dart
  /// document.events.listen((event) {
  ///   switch (event) {
  ///     case DocumentChangesApplied():
  ///       storage.saveChanges(event.changes);
  ///     case DocumentSnapshotUpdated():
  ///       storage.saveSnapshot(event.snapshot);
  ///     case DocumentHistoryPruned():
  ///       storage
  ///         ..deleteChanges(event.removed)
  ///         ..saveChanges(event.rewritten);
  ///   }
  /// });
  /// ```
  Stream<CRDTDocumentEvent> get events => _eventsController.stream;

  /// A stream that emits the [Change]s this document writes, in replay order.
  ///
  /// This is what a sync manager sends to its peers. A change that reached the
  /// document from somewhere else — [applyChange], [importChanges] — is not
  /// here: it is already known to whoever sent it.
  ///
  /// A view over [events]; every change on it is also reported there, carrying
  /// [ChangeSource.created].
  Stream<Change> get localChanges => _eventsController.stream.expand(
        (event) => event is DocumentChangesApplied &&
                event.source == ChangeSource.created
            ? event.changes.sorted()
            : const <Change>[],
      );

  /// A stream controller that emits an event
  /// every time the document state updates
  /// (local or remote change applied, snapshot imported/merged).
  final StreamController<void> _updatesController;

  /// A stream that emits when the document state updates.
  Stream<void> get updates => _updatesController.stream;

  /// Manages transactional batching of events
  late final TransactionManager _transactionManager;

  /// Whether this document is empty.
  /// (no changes and no snapshot)
  bool get isEmpty => _changeStore.changeCount == 0 && _lastSnapshot == null;

  /// Whether a transaction is currently active.
  bool get isInTransaction => _transactionManager.isInTransaction;

  /// Publishes [event] to [events], to be handed out once the document is
  /// settled.
  ///
  /// Rides the same outbox as the handler deltas (see [_deltaOutbox]), so a
  /// listener never reads a half-applied document and sees the moves in the
  /// order they happened. Nobody listening costs one field read.
  void _publishDocumentEvent(CRDTDocumentEvent event) {
    if (_eventsController.isClosed || !_eventsController.hasListener) {
      return;
    }
    _enqueueDeltaEvent(() {
      if (!_eventsController.isClosed) {
        _eventsController.add(event);
      }
    });
  }

  /// Flushes the operations to the [Compound] and applies the changes.
  ///
  /// 1. Compacts the operations
  /// 1. Operations are converted to [Change]s
  /// 1. Subscribers are notified about changes
  ///
  /// **Only [_transactionManager] can call this method.**
  void _transactionFlushWork(
    List<Operation> operations,
    List<Change> createdChanges,
    List<Change> ingestedChanges,
    bool otherPendingUpdates,
  ) {
    final compacted = Compound(
      operations: operations,
      handlers: _handlers,
    ).compact();

    final handlersAffectedFromErrors = <String>{};
    // The compacted operations become changes this document wrote, so they
    // join the ones [createChange] already put in that queue.
    final appliedChanges = createdChanges;

    // if generated operations are applied correctly the handlers
    // cached state can be preserved.
    // Otherwise if there is at least one operation not applied correctly
    // the handlers cached state is invalidated.
    for (final operation in compacted) {
      final change = _changeFromOp(operation);
      final applied = _internalApplyChange(change);

      // [operation.id] is the handler id: the revision bump costs a map
      // update, no envelope decode (see [_refreshHandlerCaches]).
      _handlerRevisions.update(operation.id, (r) => r + 1, ifAbsent: () => 1);

      final target = _handlers[operation.id];
      if (applied) {
        appliedChanges.add(change);
        // The operation was folded into the cache when it was registered; this
        // is where it finally gets its place in the replay order, and where
        // the deltas it collected finally get a change to belong to.
        target
          ?.._noteReplayBoundary(change)
          .._publishBufferedUpTo(change);
        for (final handler in _handlers.values) {
          if (!handlersAffectedFromErrors.contains(handler.id)) {
            handler._updateCachedVersion();
          }
        }
      } else {
        target?._invalidate(ResetCause.applyFailed);
        handlersAffectedFromErrors.add(operation.id);
      }
    }

    if (appliedChanges.isNotEmpty) {
      _publishDocumentEvent(
        DocumentChangesApplied(
          changes: appliedChanges,
          source: ChangeSource.created,
          origin: _deltaOrigin,
        ),
      );
    }
    if (ingestedChanges.isNotEmpty) {
      _publishDocumentEvent(
        DocumentChangesApplied(
          changes: ingestedChanges,
          source: ChangeSource.ingested,
          origin: _deltaOrigin,
        ),
      );
    }

    if (appliedChanges.isNotEmpty ||
        ingestedChanges.isNotEmpty ||
        otherPendingUpdates) {
      _updatesController.add(null);
    }
  }

  /// Advances the handler caches after [change] was applied to the document.
  ///
  /// Called on every path that hands the document a change **no handler has
  /// folded into its cache yet**: [createChange], [applyChange] and the import
  /// path. [registerOperation] is not one of them — it folds the operation as
  /// it registers it, long before the change exists, so its commit only has to
  /// report the replay boundary (see [_transactionFlushWork]).
  ///
  /// Such a change can sort before what a handler already holds, so an affected
  /// handler either queues it (see
  /// [CacheableStateProvider._queueRemoteChanges]) or drops its cache; the
  /// others have their version updated.
  void _foldOrDropCachesForChange(Change change) {
    // One list for the whole pass: [_queueRemoteChanges] copies out of it, so
    // every affected handler can share it.
    final pending = <Change>[change];
    _refreshHandlerCaches(
      (handler) => handler._isAffectedByChange(change) ? pending : null,
    );
  }

  /// Batch version of [_foldOrDropCachesForChange] for a set of applied
  /// [changes].
  ///
  /// Groups the batch by handler id once (O(changes)), then refreshes the
  /// caches in a single pass (O(handlers)). This avoids the
  /// O(handlers × changes) cost of invoking the per-change variant in a loop.
  void _foldOrDropCachesForChanges(List<Change> changes) {
    if (_handlers.isEmpty) {
      return;
    }
    final affected = <String, List<Change>>{};
    for (final change in changes) {
      try {
        final handlerId =
            OperationEnvelopeCodec.decode(change.payloadBytes()).handlerId;
        final pending = affected[handlerId];
        if (pending == null) {
          affected[handlerId] = <Change>[change];
        } else if (pending.isNotEmpty) {
          pending.add(change);
          if (pending.length >
              CacheableStateProvider._maxPendingRemoteChanges) {
            // Too many to queue: mark the handler for invalidation and stop
            // holding on to its changes.
            affected[handlerId] = const <Change>[];
          }
        }
      } catch (_) {
        // Ignore changes whose envelope cannot be decoded.
      }
    }
    _refreshHandlerCaches((handler) => affected[handler.id]);
  }

  /// Refreshes every registered handler's cache after external change(s).
  ///
  /// [changesFor] answers, per handler:
  /// - `null` — untouched: its cached version is advanced to the document's
  ///   new version;
  /// - a non-empty list — the changes that target it: [revisionForHandler] is
  ///   bumped and the changes are queued, falling back to invalidation when
  ///   the handler cannot take them;
  /// - an empty list — touched, but to be invalidated outright.
  void _refreshHandlerCaches(
    List<Change>? Function(Handler<dynamic> handler) changesFor,
  ) {
    for (final handler in _handlers.values) {
      final pending = changesFor(handler);
      if (pending == null) {
        handler._updateCachedVersion();
        continue;
      }

      _handlerRevisions.update(handler.id, (r) => r + 1, ifAbsent: () => 1);
      if (!handler._queueRemoteChanges(pending)) {
        handler.invalidateCache();
        continue;
      }

      // A watched handler cannot leave the queue waiting for a read that may
      // never come, so it folds now and publishes one event per change.
      if (handler.hasDeltaListeners) {
        try {
          handler._drainPendingRemoteChanges(withDeltas: true);
        } catch (_) {
          // The drain has already dropped this handler's cache and told its
          // subscribers why. Letting the throw out would end this loop, and
          // every handler after it would keep a version the document has
          // already moved past. One handler's bad operation is not a reason to
          // leave the others behind — and reading this one still recomputes,
          // and still throws, exactly as it does when nobody is watching.
        }
      }
    }
  }

  /// Auto-registers the handler targeted by [change] when it is not yet
  /// registered and a [HandlerFactory] is available for its type.
  ///
  /// This keeps the handler registry in sync with imported data: a peer that
  /// registered the relevant factories (see [registerFactory] /
  /// `registerDefaultFactories`) sees nested handlers appear as their changes
  /// arrive, without having to call [reconstruct].
  ///
  /// It is a no-op when no factory is registered (the classic flat usage), so
  /// existing documents are completely unaffected. Children reached only
  /// through a parent reference after history pruning are not covered here
  /// (they have no change to import) — use [reconstruct] for that case.
  void _ensureHandlerForChange(Change change) {
    if (_factories.isEmpty) {
      return;
    }
    try {
      final envelope = OperationEnvelopeCodec.decode(change.payloadBytes());
      if (_handlers.containsKey(envelope.handlerId)) {
        return;
      }
      _factories[envelope.handlerType]?.call(this, envelope.handlerId);
    } catch (_) {
      // Ignore changes whose envelope cannot be decoded.
    }
  }

  /// It represents the **latest operation for each peer** of this document
  ///
  /// Example:
  /// `{client1: HLC(3, 0), client2: HLC(2, 0),client3: HLC(1, 0)}`
  ///
  /// This means that the latest operation for client1 is HLC(3, 0)
  /// (same reasoning for client2 and client3)
  VersionVector getVersionVector() {
    if (_lastSnapshot != null) {
      return _dag.versionVector.merged(_lastSnapshot!.versionVector);
    }
    return _dag.versionVector;
  }

  /// Creates a new [Change] carrying [operation].
  ///
  /// The change takes the id [registerOperation] already minted for the
  /// operation, rather than a fresh one: that id **is** the mark a
  /// last-writer-wins handler folded into its state.
  ///
  /// An operation that never went through [registerOperation] has no id yet,
  /// which is the [createChange] case: it gets one here.
  Change _changeFromOp(
    Operation operation, {
    int? physicalTime,
  }) {
    var id = operation.stamp;
    if (id == null) {
      _tickClock(physicalTime: physicalTime);
      id = OperationId(_peerId, _clock.copy());
      operation.stamp = id;
    }

    return Change(
      id: id,
      deps: _dag.frontiers,
      author: id.peerId,
      operation: operation,
    );
  }

  /// Creates a new [Change] with the given [operation]
  ///
  /// The [Change] is automatically applied to this document.
  ///
  /// Subscribers are notified about the change only on transaction commit.
  ///
  /// [operation] must be fresh: one operation belongs to one change, because
  /// the change takes the operation's id for its own. Throws a [StateError]
  /// on one that has already been through here or through
  /// [registerOperation].
  Change createChange(
    Operation operation, {
    int? physicalTime,
    Object? origin,
  }) {
    _ensureNotDisposed('createChange');

    return _withDeltaOrigin(
      origin,
      () => _createChange(operation, physicalTime: physicalTime),
    );
  }

  Change _createChange(Operation operation, {int? physicalTime}) {
    if (operation.stamp != null) {
      throw StateError(
        'Operation ${operation.type.toPayload()} already belongs to a change '
        '(${operation.stamp}). Build a new operation for a new change.',
      );
    }

    final change = _changeFromOp(operation, physicalTime: physicalTime);
    final applied = _internalApplyChange(change);

    if (applied) {
      _foldOrDropCachesForChange(change);
      _emitUpdate(changes: [change], created: true);
    }

    return change;
  }

  @override
  void registerOperation(Operation operation) {
    _ensureNotDisposed('registerOperation');

    final handler = _handlers[operation.id];

    // This is the only place that mints an operation id. At commit, the
    // `Change` reuses this id instead of minting a fresh one.
    //
    // - The fold below runs right now, before commit. A stamped handler
    //   saves this id into its state at that moment. The `Change` must
    //   carry the same id, or the wire and the handler's state would
    //   disagree about which id was actually folded;
    //
    // The tick is what [prepareMutation] does and for the same reason: an id
    // has to be strictly newer than everything this peer has written, or a
    // second write in the same millisecond would not beat the first.
    _tickClock();
    operation.stamp = OperationId(_peerId, _clock.copy());

    final openedImplicitTransaction = !isInTransaction;

    try {
      if (openedImplicitTransaction) {
        _transactionManager.begin();
      }

      _transactionManager.handleOperation(operation);

      if (handler != null) {
        try {
          // Before the fold, so a [CRDTUndoManager] reads the state the
          // operation is about to move, and after the stamp, so the inverse
          // can name it.
          _captureForUndo(handler, operation);
        } finally {
          // The commit below is in a `finally` too, so the operation reaches
          // the change store whatever happens above. The fold has to happen
          // for the same reason: a handler that skipped it would hold a state
          // its own history does not describe, for good.
          handler._internalIncrementCachedState(operation: operation);
        }
      }
    } finally {
      if (openedImplicitTransaction) {
        _transactionManager.commit();
      }
    }
  }

  /// Applies a [Change] to this document
  ///
  /// Throws [CausallyNotReadyException] if the change is not causally ready
  /// (some of its dependencies are not present in the DAG).
  bool _internalApplyChange(Change change) {
    // Check if the change already exists
    if (_changeStore.containsChangeKey(change.key)) {
      return false;
    }

    // Dependencies that were pruned from the DAG might still be present inside
    // the last snapshot. Collect missing deps so we can verify whether they
    // are implicitly satisfied by the snapshot metadata.
    final missingDeps = _missingDependencies(change.deps);

    if (missingDeps.isNotEmpty &&
        !_dependenciesCoveredBySnapshot(missingDeps)) {
      throw CausallyNotReadyException(
        'Change is not causally ready: ${change.id}',
      );
    }

    // Add the change to the store
    _changeStore.addChange(change);
    devtools.postChangedEvent(this);

    // Add the change to the DAG
    // Only wire dependencies that still exist in the DAG. Dependencies already
    // satisfied by a snapshot do not need graph edges.
    final dagDependencies = change.deps.where(_dag.containsNode).toSet();
    _dag.addNode(change.id, dagDependencies);

    // Always advance the clock past the applied change.
    _clock.receiveEvent(
      DateTime.now().millisecondsSinceEpoch,
      change.hlc,
    );

    return true;
  }

  /// Applies a [Change] to this document
  ///
  /// The [Change] must be causally ready (all its dependencies must exist
  /// in the DAG).
  /// Returns `true` if the [Change] was applied, `false` if it already existed.
  ///
  /// {@macro delta_origin}
  bool applyChange(Change change, {Object? origin}) {
    _ensureNotDisposed('applyChange');

    return _withDeltaOrigin(origin, () => _applyChange(change));
  }

  bool _applyChange(Change change) {
    final applied = _internalApplyChange(change);
    if (applied) {
      _ensureHandlerForChange(change);
      _foldOrDropCachesForChange(change);
      _emitUpdate(changes: [change]);
    }
    return applied;
  }

  /// Takes a snapshot of the document.
  ///
  /// This operation captures the current state of the document,
  /// represented by its version (frontiers).
  ///
  /// Returns a [Snapshot] representing the document's
  /// state at the current version.
  ///
  /// ### Pruning history
  /// If [pruneHistory] is `true` (default),
  /// [Change]s that are causally included in this version are removed from the
  /// internal [ChangeStore],
  /// effectively pruning the history up to the snapshot point.
  /// The internal [DAG] is also updated.
  ///
  /// {@template pruning_strategy}
  /// ### Garbage Collection & History Pruning Strategy
  ///
  /// In a distributed CRDT system, managing the log of operations ([Change]s)
  /// involves a trade-off between **Memory Usage** and
  /// **Synchronization Capability**.
  ///
  /// #### 1. Aggressive Pruning (Local Optimization)
  /// Removing history immediately after a snapshot minimizes storage/RAM usage.
  ///
  /// > **Warning:** This breaks **Delta Synchronization** for lagging peers.
  /// > If a peer requests changes that have been pruned locally, you cannot
  /// > send the missing operations. The peer will be forced to perform a
  /// > costly **Full State Transfer** (downloading the entire snapshot).
  ///
  /// #### 2. Safe Distributed Pruning (Recommended)
  /// To ensure seamless synchronization while managing memory, follow the
  /// **Stability Frontier** pattern:
  ///
  /// * **Keep History:** Take snapshots for fast loading but keep
  /// the underlying changes (`pruneHistory: false`).
  /// * **Calculate Stability:** Determine the "minimum common version" known by
  ///   all active peers (using [VersionVector.intersection]).
  /// * **Prune Safely:** Only delete changes that are **both** included in a
  ///   snapshot **and** older than the stability frontier.
  ///
  /// This ensures that you only delete history that no other peer
  /// will ever need.
  /// {@endtemplate}
  Snapshot takeSnapshot({
    bool pruneHistory = true,
  }) {
    _ensureNotDisposed('takeSnapshot');

    // Make sure every reachable nested handler is instantiated before
    // snapshotting, otherwise children never resolved on this peer would be
    // missing from the snapshot and lost on prune.
    _materializeReachable();

    final state = <String, Uint8List>{};
    var hasContainers = false;
    for (final provider in _handlers.values) {
      state[provider.id] = provider.getSnapshotState();
      if (provider is ContainerHandler) {
        hasContainers = true;
      }
    }
    // Persist the {id: type} manifest only when nested handlers are in use, so
    // the snapshot of a flat document is byte-for-byte identical to before.
    if (hasContainers) {
      state[_handlerManifestKey] = _encodeHandlerManifest({
        for (final provider in _handlers.values)
          provider.id: provider.handlerType,
      });
    }
    final snapshot = Snapshot.create(
      versionVector: getVersionVector(),
      data: state,
    );

    // Before the prune, so a consumer mirroring this document writes the
    // snapshot down before it is told to drop the changes the snapshot covers.
    _lastSnapshot = snapshot;
    _publishDocumentEvent(
      DocumentSnapshotUpdated(
        snapshot: snapshot,
        reason: SnapshotReason.taken,
      ),
    );

    if (pruneHistory) {
      _prune(snapshot.versionVector);
    }

    return snapshot;
  }

  /// Prunes the DAG and the change store.
  /// [protectUntil] represents the stability frontier (minimum common version)
  /// until which the history is protected from garbage collection.
  ///
  /// **The history is always protected until the last snapshot.**
  ///
  /// {@macro pruning_strategy}
  void garbageCollect(VersionVector protectUntil) {
    _ensureNotDisposed('garbageCollect');

    final effectiveVV = VersionVector.intersection(
      [
        protectUntil,
        _lastSnapshot?.versionVector ?? VersionVector({}),
      ],
    );
    if (effectiveVV.isEmpty) {
      return;
    }
    _prune(effectiveVV);
  }

  /// Import [Snapshot]
  ///
  /// Returns `true` if the snapshot was applied.
  ///
  /// [snapshot] is applied only if it is newer than the document snapshot.
  /// Use [shouldApplySnapshot] to check if the snapshot should be applied.
  ///
  /// Use [pruneHistory] to prune the history and reduce memory usage.
  ///
  /// {@macro pruning_strategy}
  bool importSnapshot(
    Snapshot snapshot, {
    bool pruneHistory = true,
  }) {
    _ensureNotDisposed('importSnapshot');

    if (shouldApplySnapshot(snapshot)) {
      // Before the prune, for the reason written down in [takeSnapshot].
      _lastSnapshot = snapshot;
      _publishDocumentEvent(
        DocumentSnapshotUpdated(
          snapshot: snapshot,
          reason: SnapshotReason.imported,
        ),
      );

      if (pruneHistory) {
        _prune(snapshot.versionVector);
      }

      _advanceClockPast(snapshot.versionVector);
      _bumpRevisionsForSnapshot(snapshot);

      _invalidateHandlers(ResetCause.snapshotImport);
      _emitUpdate();
      return true;
    }

    return false;
  }

  /// Merges a [Snapshot] with the current snapshot
  ///
  /// This operation is always successful, even if the snapshot is older than
  /// the current snapshot.
  ///
  /// Use [pruneHistory] to prune the history and reduce memory usage.
  ///
  /// {@macro pruning_strategy}
  void mergeSnapshot(
    Snapshot snapshot, {
    bool pruneHistory = true,
  }) {
    _ensureNotDisposed('mergeSnapshot');

    if (_lastSnapshot == null) {
      _lastSnapshot = snapshot;
    } else {
      _lastSnapshot = _lastSnapshot!.merged(snapshot);
    }
    _advanceClockPast(snapshot.versionVector);
    _bumpRevisionsForSnapshot(snapshot);

    // The merged result, not the snapshot handed in: that is what the document
    // holds now, and what a mirror has to write down.
    _publishDocumentEvent(
      DocumentSnapshotUpdated(
        snapshot: _lastSnapshot!,
        reason: SnapshotReason.merged,
      ),
    );

    if (pruneHistory) {
      _prune(_lastSnapshot!.versionVector);
    }
    _invalidateHandlers(ResetCause.snapshotMerge);
    _emitUpdate();
  }

  /// Advances the clock past every entry of [versionVector].
  void _advanceClockPast(VersionVector versionVector) {
    final physicalTime = DateTime.now().millisecondsSinceEpoch;
    for (final entry in versionVector.entries) {
      _clock.receiveEvent(physicalTime, entry.value);
    }
  }

  /// Whether the given [snapshot] should be applied.
  ///
  /// Returns `true` if the snapshot can be applied to the document.
  ///
  /// The snapshot is applied only if it is newer than the current one.
  /// This is `true` when for every peer the snapshot version vector is
  /// strictly newer than the document version vector.
  ///
  /// ### Example:
  /// - S1: `{client1: HLC(5, 0), client2: HLC(8, 0),client3: HLC(2, 0)}`
  /// - S2: `{client1: HLC(3, 0), client2: HLC(2, 0),client3: HLC(1, 0)}`
  ///
  /// `S1` can be applied to the document because for every peer
  /// the snapshot version vector is strictly newer
  /// than the document version vector.
  ///
  /// ### Example
  /// - S1: `{client1: HLC(2, 0), client2: HLC(8, 0),client3: HLC(2, 0)}`
  /// - S2: `{client1: HLC(3, 0), client2: HLC(2, 0),client3: HLC(1, 0)}`
  ///
  /// `S1` cannot be applied to the document because for client1
  /// the snapshot version vector is not strictly newer
  /// than the document version vector.
  bool shouldApplySnapshot(Snapshot snapshot) {
    if (_lastSnapshot == null) {
      return true;
    }
    return snapshot.versionVector
        .isStrictlyNewerOrEqualThan(_lastSnapshot!.versionVector);
  }

  /// Import [snapshot] and [changes].
  /// [merge] is `false` by default.
  ///
  /// Returns the number of [Change]s that were applied.
  ///
  /// Return `-1` if the import failed.
  ///
  /// [snapshot] is always applied before [changes]
  ///
  /// If [merge] is `false`
  /// [snapshot] is applied only if it is newer than
  /// the current document snapshot (snapshot is imported using
  /// [importSnapshot]), also [changes] are ignored
  /// if [snapshot] is not imported.
  ///
  /// If [merge] is `true`, [snapshot] is merged with the current snapshot
  /// (snapshot is imported using [mergeSnapshot])
  /// and [changes] are applied to the merged snapshot.
  ///
  /// For more details:
  /// - `merge`: `true` --> [mergeSnapshot] is called before [importChanges]
  /// - `merge`: `false` --> [importSnapshot] is called before [importChanges]
  ///
  /// Use [pruneHistory] to prune the history and reduce memory usage.
  ///
  /// {@macro pruning_strategy}
  int import({
    Snapshot? snapshot,
    List<Change>? changes,
    bool merge = false,
    bool pruneHistory = true,
    Object? origin,
  }) {
    _ensureNotDisposed('import');

    if (snapshot == null && changes == null) {
      return 0;
    }

    final changesToImport = changes ?? <Change>[];

    if (snapshot == null) {
      return importChanges(changesToImport, origin: origin);
    }

    if (merge) {
      mergeSnapshot(snapshot, pruneHistory: pruneHistory);
      return importChanges(changesToImport, origin: origin);
    }

    final imported = importSnapshot(snapshot, pruneHistory: pruneHistory);
    if (!imported) {
      return -1;
    }
    return importChanges(changesToImport, origin: origin);
  }

  @override
  List<Change> exportChanges({
    Set<OperationId>? from,
    VersionVector? fromVersionVector,
  }) {
    if (from == null && fromVersionVector == null) {
      return _changeStore.getAllChanges();
    }
    if (fromVersionVector != null) {
      return _changeStore.exportChangesNewerThan(fromVersionVector);
    }
    return _changeStore.exportChanges(from ?? const {}, _dag);
  }

  @override
  List<Change> changesForHandler(
    String handlerId, {
    VersionVector? fromVersionVector,
  }) {
    return _changeStore.changesForHandler(
      handlerId,
      fromVersionVector: fromVersionVector,
    );
  }

  @override
  int changeCountForHandler(String handlerId) {
    return _changeStore.changeCountForHandler(handlerId);
  }

  @override
  int revisionForHandler(String handlerId) => _handlerRevisions[handlerId] ?? 0;

  /// Bumps the revision of every handler whose state is carried by [snapshot].
  void _bumpRevisionsForSnapshot(Snapshot snapshot) {
    for (final handlerId in snapshot.data.keys) {
      if (handlerId == _handlerManifestKey) {
        continue;
      }
      _handlerRevisions.update(handlerId, (r) => r + 1, ifAbsent: () => 1);
    }
  }

  /// Exports [Change]s that are newer than the provided [versionVector].
  ///
  /// A change is considered newer if its clock is strictly greater than the
  /// clock in the provided version vector for the same peer, or if the peer is
  /// not present in the provided vector.
  List<Change> exportChangesNewerThan(VersionVector versionVector) {
    return _changeStore.exportChangesNewerThan(versionVector);
  }

  /// Exports [Change]s as a compact binary format.
  ///
  /// This is a versioned, length-prefixed format designed for efficient
  /// synchronization and reduced memory overhead.
  Uint8List binaryExportChanges({Set<OperationId>? from}) {
    return ChangeCodec.encodeBlobs([
      for (final change in exportChanges(from: from)) change.toBytes(),
    ]);
  }

  /// Imports [Change]s from the compact binary format.
  ///
  /// Returns the number of [Change]s that were applied.
  ///
  /// {@macro delta_origin}
  int binaryImportChanges(Uint8List data, {Object? origin}) {
    _ensureNotDisposed('binaryImportChanges');

    return importChanges(
      [
        for (final blob in ChangeCodec.decodeBlobs(data))
          Change.fromBytes(blob),
      ],
      origin: origin,
    );
  }

  /// Imports [Change]s from another document
  ///
  /// Returns the number of [Change]s that were applied.
  ///
  /// {@macro delta_origin}
  int importChanges(List<Change> changes, {Object? origin}) {
    _ensureNotDisposed('importChanges');

    return _withDeltaOrigin(origin, () => _importChanges(changes));
  }

  int _importChanges(List<Change> changes) {
    // Sort changes topologically
    final sorted = _topologicalSort(
      changes.newerThan(getVersionVector()).toList(),
    );

    // Apply changes
    final changedApplied = <Change>[];
    for (final change in sorted) {
      try {
        if (_internalApplyChange(change)) {
          _ensureHandlerForChange(change);
          changedApplied.add(change);
        }
      } catch (e) {
        // Skip changes that can't be applied
      }
    }

    // Update the handler caches once for the whole batch instead of once per
    // change: a per-change pass would be O(handlers × changes), quadratic when
    // many handlers are present (e.g. a large nested tree).
    if (changedApplied.isNotEmpty) {
      _foldOrDropCachesForChanges(changedApplied);
      _emitUpdate(changes: changedApplied);
    }

    return changedApplied.length;
  }

  /// Create a history session from the current state.
  ///
  /// {@macro history_session}
  HistorySession toTimeTravel() {
    return HistorySession._fromLiveDocument(this);
  }

  /// Prunes the DAG and the change store up to the given version.
  void _prune(VersionVector version) {
    _dag.prune(version);
    _changeStore.prune(
      version,
      onPruned: _eventsController.hasListener
          ? (removed, rewritten) => _publishDocumentEvent(
                DocumentHistoryPruned(
                  upTo: version,
                  removed: removed,
                  rewritten: rewritten,
                ),
              )
          : null,
    );
    // The state now comes from the snapshot rather than from the changes that
    // built it, and a snapshot does not carry every identity a change did: an
    // OR-Set or OR-Map element comes back tagless. An inverse anchored to one
    // of those tags would apply and move nothing.
    _dropUndoHistory();
  }

  /// Drops what an undo is anchored to: the stacks of every
  /// [CRDTUndoManager], and the rebuilt-identity chains the handlers follow.
  void _dropUndoHistory() {
    for (final manager in _undoManagers ?? const <CRDTUndoManager>[]) {
      manager.clear();
    }
    for (final handler in _handlers.values) {
      // A cast, not a promotion: the analyzer will not narrow a [Handler] to
      // a mixin it merely applies.
      if (handler is RebuiltIdentities<Object>) {
        (handler as RebuiltIdentities<Object>).clearRebuiltIdentities();
      }
    }
  }

  /// Emits that the document state has made an update
  /// to be notified by listeners.
  ///
  /// [changes] are the ones just applied, and [created] says whether this
  /// document wrote them. Pass none for a move that applies no change, such as
  /// a snapshot import.
  ///
  /// If a transaction is active, the update
  /// is marked as pending; otherwise it is emitted immediately.
  ///
  /// Every [CRDTDocument] must call [_emitUpdate] when something happens,
  /// the only way to **directly** notify listeners
  /// is using the [_transactionManager] callbacks.
  void _emitUpdate({List<Change>? changes, bool created = false}) {
    if (changes != null) {
      _transactionManager.handleAppliedChanges(changes, created: created);
    } else {
      _transactionManager.requestUpdate();
    }
  }

  /// Sorts [Change]s topologically
  ///
  /// Returns a list of [Change]s sorted such that
  /// dependencies come before dependents.
  List<Change> _topologicalSort(List<Change> changes) {
    final result = <Change>[];

    if (changes.isEmpty) {
      return result;
    }

    // Create a map for O(1) lookup
    final changeMap = <OperationId, Change>{};

    // Build a graph of dependencies
    final graph = <OperationId, Set<OperationId>>{};
    final inDegree = <OperationId, int>{};

    for (final change in changes) {
      graph[change.id] = {};
      inDegree[change.id] = 0;
      changeMap[change.id] = change;
    }

    for (final change in changes) {
      for (final dep in change.deps) {
        // Only consider dependencies within the changes we're sorting
        if (graph.containsKey(dep)) {
          graph[dep]!.add(change.id);
          inDegree[change.id] = (inDegree[change.id] ?? 0) + 1;
        }
      }
    }

    // Perform topological sort (Kahn's algorithm)
    final queue = ListQueue<OperationId>.of(
      changes.where((c) => inDegree[c.id] == 0).map((c) => c.id),
    );

    while (queue.isNotEmpty) {
      final id = queue.removeFirst();
      final change = changeMap[id]!;
      result.add(change);

      for (final dependent in graph[id]!) {
        inDegree[dependent] = inDegree[dependent]! - 1;
        if (inDegree[dependent] == 0) {
          queue.add(dependent);
        }
      }
    }

    // Check for cycles
    if (result.length != changes.length) {
      throw const ChangesCycleException('Cycle detected in changes');
    }

    return result;
  }

  /// Invalidates the cache of all handlers.
  ///
  /// [cause] is what a watcher is told: these paths replace the base the
  /// replay starts from, so no delta can describe them.
  void _invalidateHandlers(ResetCause cause) {
    for (final handler in _handlers.values) {
      handler._invalidate(cause);
    }
    if (cause == ResetCause.snapshotImport ||
        cause == ResetCause.snapshotMerge) {
      // A snapshot replaces the base the state is replayed from, so the
      // identities an inverse is anchored to may not resolve any more. The
      // prune these paths usually run drops the same thing; a snapshot
      // imported with `pruneHistory: false` never reaches it.
      _dropUndoHistory();
    }
  }

  /// Runs [action] within a transaction, committing at the end.
  ///
  /// Nested transactions are supported and will only flush once the outermost
  /// transaction is committed.
  ///
  /// At the end of the transaction, contiguous operations can be compacted
  /// into fewer operations through compound algorithms ([Handler.compound])
  /// to reduce the number of changes created.
  ///
  /// {@template delta_origin}
  /// [origin] is reported on the [HandlerDelta] events this produces, and is
  /// `null` when none is given. Pass the object a consumer tags its own
  /// writes with, so it can skip its own echo; a [HandlerReset] carries none.
  /// A nested call that names none keeps the origin of the outer one.
  /// {@endtemplate}
  T runInTransaction<T>(T Function() action, {Object? origin}) {
    _ensureNotDisposed('runInTransaction');

    return _withDeltaOrigin(
      origin,
      () => _transactionManager.run<T>(action),
    );
  }

  /// Returns a string representation of this document
  @override
  String toString() {
    return 'CRDTDocument(peerId: $_peerId, changes: '
        '${_changeStore.changeCount}, version: ${version.length} frontiers)';
  }

  /// Returns the set of dependencies that are not currently present
  /// in the DAG. These are the candidates that might be covered by
  /// a snapshot.
  Set<OperationId> _missingDependencies(Set<OperationId> deps) {
    if (deps.isEmpty) {
      return <OperationId>{};
    }

    final missing = <OperationId>{};
    for (final dep in deps) {
      if (!_dag.containsNode(dep)) {
        missing.add(dep);
      }
    }
    return missing;
  }

  /// Verifies that every dependency in [deps] is included
  /// in the latest snapshot version vector.
  ///
  /// Returns `true` if the snapshot proves the missing deps were
  /// compacted away, meaning the change is still causally ready.
  bool _dependenciesCoveredBySnapshot(Set<OperationId> deps) {
    if (deps.isEmpty) {
      return true;
    }
    if (_lastSnapshot == null) {
      return false;
    }

    final versionVector = _lastSnapshot!.versionVector;
    for (final dep in deps) {
      if (!versionVector.hasSeen(dep.peerId, dep.hlc)) {
        return false;
      }
    }
    return true;
  }

  /// Disposes of the document
  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }

    _eventsController.close();
    _updatesController.close();
    for (final manager in [...?_undoManagers]) {
      manager.dispose();
    }
    _undoManagers = null;
    super.dispose();
  }
}

/// Reserved [Snapshot] data key holding the `{handlerId: handlerType}` manifest
/// used to reconstruct nested handlers after history pruning. The leading
/// control character keeps it from colliding with any real handler id.
const String _handlerManifestKey = 'crdt_lf/handler-manifest';

/// The version of the manifest blob this build writes and reads.
const int _handlerManifestVersion = 1;

/// Encodes a `{id: type}` manifest as `[u8 version][uvarint count]` followed,
/// per entry, by `[uvarint idLen][utf8 id][uvarint typeLen][utf8 type]`.
Uint8List _encodeHandlerManifest(Map<String, String> manifest) {
  final out = BytesBuilder(copy: false)..addByte(_handlerManifestVersion);
  UVarint.write(manifest.length, out);
  for (final entry in manifest.entries) {
    UVarint.writeString(entry.key, out);
    UVarint.writeString(entry.value, out);
  }
  return out.toBytes();
}

/// Decodes a manifest produced by [_encodeHandlerManifest].
Map<String, String> _decodeHandlerManifest(Uint8List bytes) {
  final manifest = <String, String>{};
  var offset = SnapshotBlob.read(
    bytes,
    version: _handlerManifestVersion,
    name: 'handler manifest',
  );
  final countRec = UVarint.read(bytes, offset: offset);
  offset = countRec.nextOffset;
  for (var i = 0; i < countRec.value; i += 1) {
    final idRecord = UVarint.readString(
      bytes,
      offset: offset,
      what: 'handler manifest id',
    );
    offset = idRecord.nextOffset;

    final typeRecord = UVarint.readString(
      bytes,
      offset: offset,
      what: 'handler manifest type',
    );
    offset = typeRecord.nextOffset;

    manifest[idRecord.value] = typeRecord.value;
  }
  return manifest;
}
