import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/capabilities/data_requirements_tracker.dart';
import 'package:crdt_lf/src/change/change_log.dart';
import 'package:crdt_lf/src/compound/compound.dart';
import 'package:crdt_lf/src/devtools/devtools.dart' as devtools;
import 'package:crdt_lf/src/document/document_clock.dart';
import 'package:crdt_lf/src/document/document_events.dart';
import 'package:crdt_lf/src/document/event_outbox.dart';
import 'package:crdt_lf/src/snapshot/blob_version.dart';
import 'package:crdt_lf/src/snapshot/records.dart';
import 'package:crdt_lf/src/snapshot/snapshot_state.dart';
import 'package:crdt_lf/src/transaction/transaction_manager.dart';
import 'package:crdt_lf/src/utils/bytes.dart';
import 'package:crdt_lf/src/utils/fnv1a.dart';
import 'package:crdt_lf/src/utils/uuid.dart';
import 'package:hlc_dart/hlc_dart.dart';

// [Handler] shares this library so the hooks the framework calls on it can stay
// private. See the "Extension points" section of its documentation for the
// members a custom handler is meant to override.
part '../handler/handler.dart';
part 'cache_coordinator.dart';
part 'deletions_registry.dart';
part 'handler_deletions.dart';
part 'delta_provider.dart';
part 'handler_registry.dart';
part 'history.dart';
// The mixins a consumer of the document is built from, and the read-only
// document a [HistorySession] walks through.
part 'providers.dart';
part 'snapshot_writer.dart';
// Undo, which is written as new inverse operations rather than as a removal.
part 'undo_manager.dart';
part 'undo_hub.dart';

/// Defines the foundational contract for a CRDT document.
///
/// This abstract class serves as the common interfaces between
/// the live [CRDTDocument] and the static read-only document.
abstract class BaseCRDTDocument {
  /// Creates a document with no handler open.
  BaseCRDTDocument() : this._(_HandlerRegistry());

  BaseCRDTDocument._(_HandlerRegistry registry)
      : _outbox = EventOutbox(),
        _registry = registry,
        _cache = _CacheCoordinator(registry);

  bool _isDisposed = false;

  final EventOutbox _outbox;

  final _HandlerRegistry _registry;

  final _CacheCoordinator _cache;

  /// Who asked for the work running right now, stamped onto the delta events it
  /// produces; `null` outside any call that named one.
  ///
  /// A document that takes no operation never has one.
  Object? get _deltaOrigin => null;

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
  /// a snapshot carrying its state is imported/merged,
  /// or it or a handler it references is deleted.
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

  /// The operations of the handler [handlerId] registered in the open
  /// transaction, which no change carries yet.
  List<Operation> _uncommittedOperations(String handlerId) => const [];

  /// Opens [handler] on this document, under its own id.
  ///
  /// Called by the [Handler] constructor, so a handler is on its document from
  /// the moment it exists. Throws [HandlerAlreadyRegisteredException] when the
  /// id is taken — building a second handler under one id is the mistake
  /// [handler] exists to avoid — and what [_HandlerDeletions.checkOpening]
  /// throws for a deleted or reserved id.
  void _registerHandler(Handler<dynamic> handler) {
    // Names the call the user actually made: they built a handler, they never
    // reach this method by name.
    _ensureNotDisposed('Handler constructor');

    _deletions.checkOpening(handler);
    handler._document = this;
    _registry.add(handler);
  }

  /// Closes the handler with [id] on this document, and returns it.
  Handler<dynamic>? _unregisterHandler(String id) => _registry.remove(id);

  _HandlerDeletions<BaseCRDTDocument> get _deletions;

  /// Generates a globally-unique id for a handler created dynamically.
  ///
  /// The id is a random UUID.
  /// It is generated by the creator and carried inside the [HandlerRef],
  /// so remote peers reuse the same id verbatim when reconstructing the tree.
  String newHandlerId() => generateUuid();

  /// Declares a kind this peer never opens itself, so a reference to one can
  /// still be rebuilt.
  ///
  /// A handler declares its own kind as it is constructed, so this is only for
  /// a kind that arrives without being opened here. Declaring the same kind
  /// twice replaces what was there.
  ///
  /// ```dart
  /// document.register(CRDTFugueTextHandler.spec);
  /// document.register(CRDTListHandler.spec<Todo>('todo-list'));
  /// ```
  ///
  /// Throws [DocumentDisposedException] on a disposed document.
  void register<T extends Handler<dynamic>>(HandlerSpec<T> spec) {
    _ensureNotDisposed('register');

    _registry.specs[spec.type] = spec;
  }

  /// The handler [spec] describes under [id], or the one already open there.
  ///
  /// Safe to call again, unlike a constructor.
  ///
  /// ```dart
  /// final root = doc.handler(CRDTMapRefHandler.spec, 'root');
  /// ```
  ///
  /// Throws [HandlerAlreadyRegisteredException] when [id] is taken by a handler
  /// of another kind, and [HandlerDeletedException] when [id] was deleted.
  /// Throws an [ArgumentError] for `crdt_lf/deleted-handlers`, the id the
  /// document keeps its deletes under.
  T handler<T extends Handler<dynamic>>(HandlerSpec<T> spec, String id) {
    _HandlerDeletions.checkNotReserved(id);
    return _registry.open(this, spec, id);
  }

  /// Resolves [ref] to a handler instance.
  ///
  /// Returns the already-registered handler with `ref.id`, or instantiates it
  /// via the [HandlerSpec] registered for `ref.type` (the constructor
  /// self-registers it). Returns `null` when nothing is registered for it, or
  /// when the handler was deleted.
  Handler<dynamic>? resolveHandler(HandlerRef ref) {
    if (_deletions.hides(ref.id)) {
      return null;
    }
    return _registry.resolve(this, ref);
  }

  /// Whether the handler with [handlerId] was deleted with [deleteHandler],
  /// on this peer or on a peer whose changes this document holds.
  bool isDeleted(String handlerId) => _deletions.isDeleted(handlerId);

  /// Deletes [handler], and every handler reachable from it through
  /// references, for every peer.
  ///
  /// {@template delete_handler}
  /// A delete is final and wins over any concurrent edit of the deleted
  /// handlers. Once deleted, a handler is closed: it leaves the registry, its
  /// `watch` stream ends, and a write to it throws
  /// [HandlerDeletedException]. Opening or building one under the same id
  /// throws too, and [resolveHandler] returns `null`.
  ///
  /// The next [CRDTDocument.takeSnapshot] leaves its state out, so a prune
  /// frees its data. A [CRDTUndoManager] cannot bring it back. Its id stays:
  /// every snapshot carries it, plus a few bytes, for good.
  ///
  /// A child that another container also references is deleted for that
  /// container too. A child added to a container while another peer deletes
  /// it is deleted as well, once a peer that can build the container holds
  /// both changes.
  /// {@endtemplate}
  ///
  /// Deleting a handler that is already deleted does nothing.
  ///
  /// Throws an [ArgumentError] when [handler] belongs to another document.
  void deleteHandler(Handler<dynamic> handler);

  /// Deletes the handler [ref] points at, and every handler reachable from
  /// it, for every peer.
  ///
  /// {@macro delete_handler}
  ///
  /// Works when this peer cannot build the handler, as only the id is needed.
  /// Its children are then deleted by the first peer that can build it.
  ///
  /// Deleting a handler that is already deleted does nothing. Throws an
  /// [ArgumentError] for the id the document keeps its deletes under.
  void deleteHandlerRef(HandlerRef ref);

  /// Runs [action] as one transaction: its operations reach the other peers
  /// together.
  ///
  /// See [CRDTDocument.runInTransaction].
  T runInTransaction<T>(T Function() action, {Object? origin});

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
    for (final handler in _registry.values) {
      handler._closeDeltas();
    }
    _registry.clear();
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
  })  : _log = ChangeLog(),
        _documentId = documentId ?? generateUuid(),
        _clock = DocumentClock(
          peerId ?? PeerId.generate(),
          initial: initialClock,
        ),
        _undo = _UndoHub(),
        _snapshots = SnapshotState() {
    _deletions = _LiveDeletions(this);
    _transactionManager = TransactionManager(
      flushWork: _transactionFlushWork,
      onFlushed: _onTransactionFlushed,
    );
    _documentEvents = DocumentEvents(
      outbox: _outbox,
      transactions: _transactionManager,
    );
    devtools.handleCreated(this);
  }

  final ChangeLog _log;

  /// The ID of the document/resource
  final String _documentId;

  final DocumentClock _clock;

  @override
  late final _LiveDeletions _deletions;

  /// The kinds every document of this build reads, whatever its handlers.
  ///
  /// [describeBuildCapabilities] always names them. Add them to capabilities
  /// written by hand.
  static final DocumentCapabilities builtInCapabilities = DocumentCapabilities({
    _DeletionsRegistry.spec.type: _DeletionsRegistry.spec.formats,
    SnapshotRecords.unfoldedKey: SnapshotRecords.unfoldedFormats,
  });

  @override
  void deleteHandler(Handler<dynamic> handler) {
    _ensureNotDisposed('deleteHandler');
    if (!identical(handler.doc, this)) {
      throw ArgumentError.value(
        handler.id,
        'handler',
        'Belongs to another document',
      );
    }
    _deletions.delete([HandlerRef.of(handler)]);
  }

  @override
  void deleteHandlerRef(HandlerRef ref) {
    _ensureNotDisposed('deleteHandlerRef');
    _HandlerDeletions.checkNotReserved(ref.id);
    _deletions.delete([ref]);
  }

  @override
  void _registerHandler(Handler<dynamic> handler) {
    super._registerHandler(handler);
    _cache.track(handler);
  }

  @override
  Handler<dynamic>? _unregisterHandler(String id) {
    _cache.forget(id);
    return super._unregisterHandler(id);
  }

  /// The unfolded changes the snapshot carries for [handlerId]; none when they
  /// cannot be read.
  List<Change> _readableUnfoldedChanges(String handlerId) {
    try {
      return SnapshotRecords.unfoldedChangesFor(_lastSnapshot, handlerId) ??
          const [];
    } on FormatException {
      return const [];
    }
  }

  /// What [read] returns off the handler [id] of kind [type], built for the
  /// time of the call; `null` when no spec of [type] is registered.
  ///
  /// For an id no handler is open under. The handler is closed again
  /// afterwards, whatever [read] does.
  T? _readClosed<T>(
    String id,
    String type,
    T Function(Handler<dynamic> handler) read,
  ) {
    assert(_registry[id] == null, 'Handler $id is open');
    final spec = _registry.specs[type];
    if (spec == null) {
      return null;
    }
    try {
      return read(spec.create(this, id));
    } finally {
      // A constructor that threw may have opened nothing.
      if (_registry[id] != null) {
        _unregisterHandler(id);
      }
    }
  }

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

  final _UndoHub _undo;

  /// Closes the undo steps a committed transaction filled, then hands out the
  /// delta events it produced.
  ///
  /// In that order: a listener reacting to a delta reads a settled
  /// [CRDTUndoManager.canUndo].
  void _onTransactionFlushed() {
    _undo.closeEntries();
    _outbox.flush();
  }

  @override
  PeerId get peerId => _clock.peerId;

  @override
  String get documentId => _documentId;

  @override
  HybridLogicalClock get hlc => _clock.now;

  final SnapshotState _snapshots;

  @override
  Snapshot? get _lastSnapshot => _snapshots.current;

  /// Moves the document's clock forward, as registering an operation would.
  ///
  /// Spends a clock value without producing an operation. Use it to bring two
  /// documents' clocks level, so they write in the same tick on purpose. It is
  /// not a way to keep time.
  @override
  void prepareMutation() {
    _ensureNotDisposed('prepareMutation');
    _clock.tick();
  }

  @override
  Set<OperationId> get version {
    return _log.frontiers;
  }

  /// All handlers currently registered on this document, keyed by their id.
  ///
  /// Intended for read-only introspection (devtools, debugging). Do not mutate.
  Map<String, Handler<dynamic>> get registeredHandlers => _registry.publicView;

  /// Rebuilds every handler reachable from the data this document holds.
  ///
  /// For a peer that received only changes or a snapshot and does not know the
  /// structure in advance. Only kinds this document knows are rebuilt — see
  /// [register]. Reading from a known root with `getRef` or `resolved` works
  /// without this.
  void reconstruct() {
    _ensureNotDisposed('reconstruct');

    _registry.reconstruct(
      this,
      changes: [
        ...exportChanges(),
        for (final id in SnapshotRecords.unfoldedEntriesOf(_lastSnapshot).keys)
          ..._readableUnfoldedChanges(id),
      ],
      manifest: _HandlerRegistry.manifestOf(_lastSnapshot),
    );
  }

  /// What this document's data is written in, folded as changes arrive.
  ///
  /// Answers [describeDataRequirements] and writes the record every snapshot
  /// carries. See [DataRequirementsTracker.isStarted] for what it costs.
  final DataRequirementsTracker _dataRequirements = DataRequirementsTracker();

  /// Starts the fold, if nobody has yet.
  void _trackDataRequirements() => _dataRequirements.start(
        lastSnapshot: _lastSnapshot,
        changes: exportChanges,
      );

  /// The formats this document's data is written in, by handler kind.
  ///
  /// Read from the changes and the last snapshot, so it answers on a document
  /// that has opened no handler. Compare it with [describeBuildCapabilities] to
  /// find the kinds this peer cannot read.
  ///
  /// [HandlerFormats.blobVersions] is `null` for a kind known from its changes
  /// alone: an envelope carries no snapshot version.
  ///
  /// Throws [DocumentDisposedException] on a disposed document.
  DocumentRequirements describeDataRequirements() {
    _ensureNotDisposed('describeDataRequirements');
    _trackDataRequirements();

    return _dataRequirements.describe();
  }

  /// What this build can read, by handler kind.
  ///
  /// Names the kinds this document has a handler of, those passed to
  /// [register] and the [builtInCapabilities]. Builds nothing.
  ///
  /// A kind is absent when nothing opened or declared it, which is why a
  /// description read off a document is sent as incomplete: silence means "not
  /// set up here", not "cannot read".
  ///
  /// Throws [DocumentDisposedException] on a disposed document.
  DocumentCapabilities describeBuildCapabilities() {
    _ensureNotDisposed('describeBuildCapabilities');

    // Only the specs: a handler declares its kind as it opens, so every kind
    // this document has open is already a key here.
    return DocumentCapabilities({
      ...builtInCapabilities.byHandlerType,
      for (final spec in _registry.specs.values) spec.type: spec.formats,
    });
  }

  /// The handlers that are not referenced by any other container handler,
  /// i.e. the entry points of the nested tree.
  Iterable<Handler<dynamic>> roots() => _registry.roots();

  late final DocumentEvents _documentEvents;

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
  /// **Broadcast, and nothing is replayed.** A move made before you subscribe
  /// is not reported to you: subscribe before the document is written to, or
  /// read the state you missed with [exportChanges] and [takeSnapshot]. With no
  /// listener the document builds no event at all, so an unused [events] costs
  /// nothing.
  ///
  /// Every event carries the `origin` of the call behind it, so a consumer can
  /// recognise its own writes — a persistence adapter can subscribe first and
  /// still skip the restore it performs itself. See [import].
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
  Stream<CRDTDocumentEvent> get events => _documentEvents.events;

  /// A stream that emits the [Change]s this document writes, in replay order.
  ///
  /// This is what a sync manager sends to its peers. A change that reached the
  /// document from somewhere else — [applyChange], [importChanges] — is not
  /// here: it is already known to whoever sent it.
  ///
  /// A view over [events]; every change on it is also reported there, carrying
  /// [ChangeSource.created].
  Stream<Change> get localChanges => _documentEvents.localChanges;

  /// A stream that emits when the document state updates.
  Stream<void> get updates => _documentEvents.updates;

  /// Manages transactional batching of events
  late final TransactionManager _transactionManager;

  /// Whether this document is empty.
  /// (no changes and no snapshot)
  bool get isEmpty => _log.changeCount == 0 && _lastSnapshot == null;

  /// Whether a transaction is currently active.
  bool get isInTransaction => _transactionManager.isInTransaction;

  /// Flushes the operations to the [Compound] and applies the changes.
  ///
  /// 1. Compacts the operations
  /// 1. Operations are converted to [Change]s
  /// 1. Subscribers are notified about changes
  ///
  /// **Only [_transactionManager] can call this method.**
  void _transactionFlushWork(TransactionWork work) {
    final compacted = Compound(
      operations: work.operations,
      handlers: _registry.view,
    ).compact();

    // The changes the compacted operations become. They belong at the end of
    // the batches this transaction collected: they only exist now, at the
    // commit, while every batch already queued happened before it.
    final appliedChanges = <Change>[];

    // An operation that fails to apply drops its own handler's cache, and only
    // that one.
    for (final operation in compacted) {
      final change = _changeFromOp(operation);
      final applied = _internalApplyChange(change);

      // [operation.id] is the handler id: the revision bump costs a map
      // update, no envelope decode.
      _cache.bumpState(operation.id);

      final target = _registry[operation.id];
      if (applied) {
        appliedChanges.add(change);
        // The operation was folded into the cache when it was registered; this
        // is where it finally gets its place in the replay order, and where
        // the deltas it collected finally get a change to belong to.
        target
          ?.._noteReplayBoundary(change)
          .._publishBufferedUpTo(change);
      } else {
        target?._invalidate(ResetCause.applyFailed);
      }
    }

    _deletions.sync();

    // In order, so a consumer reading the stream sees the moves in the order
    // they happened. A transaction that takes changes in before it writes its
    // own reports the ingest first, and the changes it wrote name the ingested
    // ones among their dependencies — and a snapshot taken in the middle sits
    // where it was taken, so the prune that follows it never reaches a
    // listener before the change it removed.
    //
    // Straight to the outbox: the transaction is over, so `queueEvent` would
    // answer `false` for every one of them anyway.
    for (final event in work.events) {
      _documentEvents.publish(event);
    }
    if (appliedChanges.isNotEmpty) {
      _documentEvents.publish(
        DocumentChangesApplied(
          changes: appliedChanges,
          source: ChangeSource.created,
          // Read here on purpose: the operations were collected under this
          // origin, and only become changes at the commit.
          origin: _deltaOrigin,
        ),
      );
    }

    // Only the applied changes count here, not every event: `updates` has
    // always meant "the document took a change in", and a snapshot has never
    // woken it.
    if (appliedChanges.isNotEmpty ||
        work.events.any((event) => event is DocumentChangesApplied) ||
        work.otherPendingUpdates) {
      _documentEvents.notifyUpdates();
    }
  }

  /// Advances the handler caches after [change] was applied to the document.
  ///
  /// Called on every path that hands the document a change **no handler has
  /// folded into its cache yet**: [createChange], [applyChange] and the import
  /// path. [registerOperation] is not one of them — it folds the operation as
  /// it registers it, long before the change exists, so its commit only has to
  /// report the replay boundary (see [_transactionFlushWork]).
  void _foldOrDropCachesForChange(Change change) {
    _cache.route(change);
    _deletions.sync();
  }

  /// Batch version of [_foldOrDropCachesForChange] for a set of applied
  /// [changes].
  void _foldOrDropCachesForChanges(List<Change> changes) {
    _cache.routeAll(changes);
    _deletions.sync();
  }

  /// It represents the **latest operation for each peer** of this document
  ///
  /// Example:
  /// `{client1: HLC(3, 0), client2: HLC(2, 0),client3: HLC(1, 0)}`
  ///
  /// This means that the latest operation for client1 is HLC(3, 0)
  /// (same reasoning for client2 and client3)
  VersionVector getVersionVector() =>
      _snapshots.versionVector(_log.versionVector);

  /// The snapshot the history of this document is replayed on top of; `null`
  /// before the first one.
  ///
  /// A read-only copy: writing to its [Snapshot.data] or its
  /// [Snapshot.versionVector] throws an [UnsupportedError]. Each read returns
  /// a new copy, so compare two of them by [Snapshot.id].
  Snapshot? get snapshot => _snapshots.readOnlyCopy();

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
      id = _clock.mint(physicalTime: physicalTime);
      operation.stamp = id;
    }

    return Change(
      id: id,
      deps: _log.frontiers,
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
      _emitUpdate(changes: [change], source: ChangeSource.created);
    }

    return change;
  }

  @override
  void registerOperation(Operation operation) {
    _ensureNotDisposed('registerOperation');

    final handler = _registry[operation.id];
    if (handler == null && isDeleted(operation.id)) {
      throw HandlerDeletedException(operation.id);
    }

    // This is the only place that mints an operation id. At commit, the
    // `Change` reuses this id instead of minting a fresh one.
    //
    // - The fold below runs right now, before commit. A stamped handler
    //   saves this id into its state at that moment. The `Change` must
    //   carry the same id, or the wire and the handler's state would
    //   disagree about which id was actually folded;
    //
    // Minting ticks the clock, as [prepareMutation] does and for the same
    // reason: an id has to be strictly newer than everything this peer has
    // written, or a second write in the same millisecond would not beat the
    // first.
    operation.stamp = _clock.mint();

    final openedImplicitTransaction = !isInTransaction;

    try {
      if (openedImplicitTransaction) {
        _transactionManager.begin();
      }

      try {
        // Before the operation joins the transaction and before the fold, so
        // a [CRDTUndoManager] reads the state the operation is about to move,
        // and after the stamp, so the inverse can name it.
        if (handler != null) {
          _undo.capture(handler, operation);
        }
      } finally {
        // The commit below is in a `finally` too, so the operation reaches
        // the change store whatever happens above. The fold has to happen
        // for the same reason: a handler that skipped it would hold a state
        // its own history does not describe, for good.
        _transactionManager.handleOperation(operation);
        handler?._internalIncrementCachedState(operation: operation);
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
    if (!_log.add(change, snapshotVersion: _lastSnapshot?.versionVector)) {
      return false;
    }

    _deletions.noteApplied(change);
    if (_dataRequirements.isStarted) {
      // Here, and not on a cursor over the store: this is the one point every
      // change passes exactly once, whatever order it arrived in.
      _dataRequirements.fold(change);
    }
    devtools.postChangedEvent(this);

    // Always advance the clock past the applied change.
    _clock.receive(change.hlc);

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
      _foldOrDropCachesForChange(change);
      _emitUpdate(changes: [change], source: ChangeSource.ingested);
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
  /// It holds the state of every handler the document holds data for, open or
  /// not. A closed handler of a kind this document knows is built for the time
  /// of the snapshot. The changes of a kind it does not know ride inside the
  /// snapshot, so the prune that follows loses nothing another peer can read.
  ///
  /// Throws a [FormatException] when a handler got new changes on top of
  /// carried changes this build cannot read.
  ///
  /// A child added to a deleted container by an edit concurrent with the delete
  /// is deleted first, which writes a change (see [deleteHandler]).
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
  ///
  /// [origin] is carried by the [DocumentSnapshotUpdated] this publishes, and
  /// by the [DocumentHistoryPruned] that follows it when [pruneHistory] is on.
  Snapshot takeSnapshot({
    bool pruneHistory = true,
    Object? origin,
  }) {
    _ensureNotDisposed('takeSnapshot');

    return _withDeltaOrigin(origin, () => _takeSnapshot(pruneHistory));
  }

  Snapshot _takeSnapshot(bool pruneHistory) {
    _deletions.deleteLateChildren();
    // Make sure every reachable nested handler is instantiated before
    // snapshotting, otherwise children never resolved on this peer would be
    // missing from the snapshot and lost on prune.
    _registry.materializeReachable(this);

    final draft = _SnapshotWriter(this).write();
    final state = draft.data;
    _trackDataRequirements();
    // The blobs this snapshot rewrote replace the versions folded in before;
    // a copied blob keeps the version it was written in. One of unknown type
    // keeps them all, but for the unfolded record, which is rewritten below.
    _dataRequirements.replaceBlobVersions(
      draft.written,
      keeps: (type) =>
          draft.copiedTypes.contains(type) ||
          (draft.copiedUntyped && type != SnapshotRecords.unfoldedKey),
    );
    if (state.containsKey(SnapshotRecords.unfoldedKey)) {
      _dataRequirements.include(
        SnapshotRecords.unfoldedKey,
        SnapshotRecords.unfoldedFormats,
      );
    }
    state[SnapshotRecords.capabilitiesKey] =
        SnapshotRecords.encodeRequirements(_dataRequirements.describe());

    final snapshot = Snapshot.create(
      versionVector: getVersionVector(),
      data: state,
    );

    // Before the prune, so a consumer mirroring this document writes the
    // snapshot down before it is told to drop the changes the snapshot covers.
    _snapshots.current = snapshot;
    _documentEvents.publish(
      DocumentSnapshotUpdated(
        snapshot: snapshot,
        reason: SnapshotReason.taken,
        origin: _deltaOrigin,
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
  ///
  /// [origin] is carried by the [DocumentHistoryPruned] this publishes.
  void garbageCollect(VersionVector protectUntil, {Object? origin}) {
    _ensureNotDisposed('garbageCollect');

    _withDeltaOrigin(origin, () => _garbageCollect(protectUntil));
  }

  void _garbageCollect(VersionVector protectUntil) {
    final effectiveVV = _snapshots.prunableUpTo(protectUntil);
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
  /// {@template unreadable_snapshot}
  /// Throws a [FormatException], and leaves the document as it was, when
  /// [snapshot] carries changes in a layout this build cannot read.
  /// {@endtemplate}
  ///
  /// Use [pruneHistory] to prune the history and reduce memory usage.
  ///
  /// {@macro pruning_strategy}
  ///
  /// [origin] is carried by the [DocumentSnapshotUpdated] this publishes, and
  /// by the [DocumentHistoryPruned] that follows it when [pruneHistory] is on.
  bool importSnapshot(
    Snapshot snapshot, {
    bool pruneHistory = true,
    Object? origin,
  }) {
    _ensureNotDisposed('importSnapshot');

    return _withDeltaOrigin(
      origin,
      () => _importSnapshot(snapshot, pruneHistory),
    );
  }

  bool _importSnapshot(Snapshot snapshot, bool pruneHistory) {
    if (shouldApplySnapshot(snapshot)) {
      // First: a record this build cannot read throws before anything moves.
      SnapshotRecords.unfoldedEntriesOf(snapshot);
      // Before the prune, which is about to take away the changes this
      // snapshot stands for.
      _dataRequirements.readRecord(snapshot);

      // Before the prune, for the reason written down in [takeSnapshot].
      _snapshots.current = snapshot;
      _documentEvents.publish(
        DocumentSnapshotUpdated(
          snapshot: snapshot,
          reason: SnapshotReason.imported,
          origin: _deltaOrigin,
        ),
      );

      if (pruneHistory) {
        _prune(snapshot.versionVector);
      }

      _clock.advancePast(snapshot.versionVector);
      _cache.bumpForSnapshot(snapshot);

      _invalidateHandlers(ResetCause.snapshotImport);
      _deletions.syncSnapshot(snapshot);
      _emitUpdate();
      return true;
    }

    return false;
  }

  /// Merges a [Snapshot] with the current snapshot
  ///
  /// It succeeds even when [snapshot] is older than the current one. Throws a
  /// [ConcurrentSnapshotException], and leaves the document as it was, when
  /// both hold one handler as two different blobs at concurrent versions.
  /// Changes a snapshot carries for a handler always merge.
  ///
  /// {@macro unreadable_snapshot}
  ///
  /// Use [pruneHistory] to prune the history and reduce memory usage.
  ///
  /// {@macro pruning_strategy}
  ///
  /// [origin] is carried by the [DocumentSnapshotUpdated] this publishes, and
  /// by the [DocumentHistoryPruned] that follows it when [pruneHistory] is on.
  void mergeSnapshot(
    Snapshot snapshot, {
    bool pruneHistory = true,
    Object? origin,
  }) {
    _ensureNotDisposed('mergeSnapshot');

    _withDeltaOrigin(origin, () => _mergeSnapshot(snapshot, pruneHistory));
  }

  void _mergeSnapshot(Snapshot snapshot, bool pruneHistory) {
    // First: a record this build cannot read throws before anything moves.
    SnapshotRecords.unfoldedEntriesOf(snapshot);
    final merged = _snapshots.merge(snapshot);
    _dataRequirements.readRecord(snapshot);
    _clock.advancePast(snapshot.versionVector);
    _cache.bumpForSnapshot(snapshot);

    // The merged result, not the snapshot handed in: that is what the document
    // holds now, and what a mirror has to write down.
    _documentEvents.publish(
      DocumentSnapshotUpdated(
        snapshot: merged,
        reason: SnapshotReason.merged,
        origin: _deltaOrigin,
      ),
    );

    if (pruneHistory) {
      _prune(merged.versionVector);
    }
    _invalidateHandlers(ResetCause.snapshotMerge);
    _deletions.syncSnapshot(snapshot);
    _emitUpdate();
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
  bool shouldApplySnapshot(Snapshot snapshot) =>
      _snapshots.shouldApply(snapshot);

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
  /// (snapshot is imported using [mergeSnapshot], and throws as it does)
  /// and [changes] are applied to the merged snapshot.
  ///
  /// For more details:
  /// - `merge`: `true` --> [mergeSnapshot] is called before [importChanges]
  /// - `merge`: `false` --> [importSnapshot] is called before [importChanges]
  ///
  /// Use [pruneHistory] to prune the history and reduce memory usage.
  ///
  /// [origin] is carried by every event this publishes, so a consumer of
  /// [events] can recognise the moves it asked for — a persistence adapter
  /// reading its own copy back, say — and skip writing them down again.
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
      mergeSnapshot(snapshot, pruneHistory: pruneHistory, origin: origin);
      return importChanges(changesToImport, origin: origin);
    }

    final imported = importSnapshot(
      snapshot,
      pruneHistory: pruneHistory,
      origin: origin,
    );
    if (!imported) {
      return -1;
    }
    return importChanges(changesToImport, origin: origin);
  }

  @override
  List<Change> exportChanges({
    Set<OperationId>? from,
    VersionVector? fromVersionVector,
  }) =>
      _log.exportChanges(from: from, fromVersionVector: fromVersionVector);

  @override
  List<Change> changesForHandler(
    String handlerId, {
    VersionVector? fromVersionVector,
  }) =>
      _log.changesForHandler(handlerId, fromVersionVector: fromVersionVector);

  @override
  List<Operation> _uncommittedOperations(String handlerId) => [
        for (final operation in _transactionManager.pendingOperations)
          if (operation.id == handlerId) operation,
      ];

  @override
  int changeCountForHandler(String handlerId) =>
      _log.changeCountForHandler(handlerId);

  @override
  int revisionForHandler(String handlerId) => _cache.revisionOf(handlerId);

  /// Exports [Change]s that are newer than the provided [versionVector].
  ///
  /// A change is considered newer if its clock is strictly greater than the
  /// clock in the provided version vector for the same peer, or if the peer is
  /// not present in the provided vector.
  List<Change> exportChangesNewerThan(VersionVector versionVector) =>
      _log.exportChangesNewerThan(versionVector);

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
    final sorted = ChangeLog.sortTopologically(
      changes.newerThan(getVersionVector()).toList(),
    );

    // Apply changes
    final changedApplied = <Change>[];
    for (final change in sorted) {
      try {
        if (_internalApplyChange(change)) {
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
      _emitUpdate(changes: changedApplied, source: ChangeSource.ingested);
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
    _deletions.notePrune();
    final before = _log.frontiers;
    _log.prune(
      version,
      onPruned: _documentEvents.hasListener
          ? (removed, rewritten) => _documentEvents.publish(
                DocumentHistoryPruned(
                  upTo: version,
                  removed: removed,
                  rewritten: rewritten,
                  origin: _deltaOrigin,
                ),
              )
          : null,
    );
    // New frontiers: the caches were built on a history this document no
    // longer holds, so the next read rebuilds them from the snapshot.
    if (!setEquals(before, _log.frontiers)) {
      _cache.markAllStale();
    }
    // The state now comes from the snapshot rather than from the changes that
    // built it, and a snapshot does not carry every identity a change did: an
    // OR-Set or OR-Map element comes back tagless. An inverse anchored to one
    // of those tags would apply and move nothing.
    _undo.dropHistory(_registry.values);
  }

  /// Emits that the document state has made an update
  /// to be notified by listeners.
  ///
  /// [changes] are the ones just applied and [source] says how they reached
  /// this document. Pass neither for a move that applies no change, such as a
  /// snapshot import.
  ///
  /// The batch is turned into its event **here**, not at the commit: this is
  /// where the move happens, so this is where [_deltaOrigin] still holds the
  /// origin of the call behind it. A nested call restores the outer origin
  /// long before the commit runs.
  ///
  /// If a transaction is active, the update
  /// is marked as pending; otherwise it is emitted immediately.
  ///
  /// Every [CRDTDocument] must call [_emitUpdate] when something happens,
  /// the only way to **directly** notify listeners
  /// is using the [_transactionManager] callbacks.
  void _emitUpdate({List<Change>? changes, ChangeSource? source}) =>
      _documentEvents.reportMove(
        changes: changes,
        source: source,
        origin: _deltaOrigin,
      );

  /// Invalidates the cache of all handlers.
  ///
  /// [cause] is what a watcher is told: these paths replace the base the
  /// replay starts from, so no delta can describe them.
  void _invalidateHandlers(ResetCause cause) {
    _cache.invalidateAll(cause);
    if (cause == ResetCause.snapshotImport ||
        cause == ResetCause.snapshotMerge) {
      // A snapshot replaces the base the state is replayed from, so the
      // identities an inverse is anchored to may not resolve any more. The
      // prune these paths usually run drops the same thing; a snapshot
      // imported with `pruneHistory: false` never reaches it.
      _undo.dropHistory(_registry.values);
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
  @override
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
    return 'CRDTDocument(peerId: $peerId, changes: '
        '${_log.changeCount}, version: ${version.length} frontiers)';
  }

  /// Disposes of the document
  ///
  /// Events already published but not handed out yet are delivered first. A
  /// consumer that mirrors this document — a persistence adapter — would
  /// otherwise never learn about the last move, because the closed controller
  /// drops what the outbox still holds.
  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }

    _outbox.flush();
    _documentEvents.close();
    _undo.dispose();
    super.dispose();
    _cache.clear();
  }
}
