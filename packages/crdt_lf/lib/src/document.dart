import 'dart:async';
import 'dart:convert';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/compound/compound.dart';
import 'package:crdt_lf/src/devtools/devtools.dart' as devtools;
import 'package:crdt_lf/src/transaction/transaction_manager.dart';
import 'package:hlc_dart/hlc_dart.dart';

// TODO(mattia): after transaction support create compound operations.
// A mechanism to group operations together and apply them atomically.

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
class CRDTDocument {
  /// Creates a new [CRDTDocument] with the given identifiers.
  ///
  /// - [peerId]: the identifier of the local peer (author of operations).
  ///   If not provided, a new one is generated.
  /// - [documentId]: the identifier of the document. If not provided, a new
  ///   random identifier is generated.
  CRDTDocument({
    PeerId? peerId,
    String? documentId,
  })  : _dag = DAG.empty(),
        _changeStore = ChangeStore.empty(),
        _peerId = peerId ?? PeerId.generate(),
        _documentId = documentId ?? PeerId.generate().toString(),
        _clock = HybridLogicalClock.initialize(),
        _localChangesController = StreamController<Change>.broadcast(),
        _handlers = {} {
    _transactionManager = TransactionManager(
      flushWork: _transactionFlushWork,
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

  /// Gets the peer ID of this document
  PeerId get peerId => _peerId;

  /// Gets the document ID of this document
  String get documentId => _documentId;

  /// Gets the current timestamp of this document
  HybridLogicalClock get hlc => _clock.copy();

  /// Gets the current version of this document (the frontiers of the DAG)
  Set<OperationId> get version => _dag.frontiers;

  /// A stream controller for locally generated changes.
  final StreamController<Change> _localChangesController;

  /// A stream that emits [Change]s created locally by this document.
  Stream<Change> get localChanges => _localChangesController.stream;

  /// A stream controller that emits an event
  /// every time the document state updates
  /// (local or remote change applied, snapshot imported/merged).
  final StreamController<void> _updatesController =
      StreamController<void>.broadcast();

  /// A stream that emits when the document state updates.
  Stream<void> get updates => _updatesController.stream;

  /// The registered snapshot providers
  final Map<String, Handler<dynamic>> _handlers;

  /// The last snapshot of this document
  Snapshot? _lastSnapshot;

  /// Manages transactional batching of events
  late final TransactionManager _transactionManager;

  /// Whether this document is empty.
  /// (no changes and no snapshot)
  bool get isEmpty => _changeStore.changeCount == 0 && _lastSnapshot == null;

  /// Whether a transaction is currently active.
  bool get isInTransaction => _transactionManager.isInTransaction;

  /// Flushes the operations to the [Compound] and applies the changes.
  ///
  /// 1. Compacts the operations
  /// 1. Operations are converted to [Change]s
  /// 1. Subscribers are notified about changes
  ///
  /// **Only [_transactionManager] can call this method.**
  void _transactionFlushWork(
    List<Operation> operations,
    List<Change> changes,
    bool otherPendingUpdates,
  ) {
    final compacted = Compound(
      operations: operations,
      handlers: _handlers,
    ).compact();

    final handlersAffectedFromErrors = <String>{};
    final appliedChanges = changes;

    // if generated operations are applied correctly the handlers
    // cached state can be preserved.
    // Otherwise if there is at least one operation not applied correctly
    // the handlers cached state is invalidated.
    for (final operation in compacted) {
      final change = _changeFromOp(operation);
      final applied = _internalApplyChange(change);

      if (applied) {
        appliedChanges.add(change);
        for (final handler in _handlers.values) {
          if (!handlersAffectedFromErrors.contains(handler.id)) {
            handler._updateCachedVersion();
          }
        }
      } else {
        _handlers[operation.id]?.invalidateCache();
        handlersAffectedFromErrors.add(operation.id);
      }
    }

    if (!_localChangesController.isClosed) {
      for (final change in appliedChanges.sorted()) {
        _localChangesController.add(change);
      }
    }

    if (appliedChanges.isNotEmpty || otherPendingUpdates) {
      _updatesController.add(null);
    }
  }

  /// [Change]s applied by external sources could not be incremental.
  /// So the affected handlers are invalidated,
  /// while others have their version updated.
  ///
  /// After the handlers are updated is emitted
  /// an update request.
  void _reactToAppliedExternalChange(Change change) {
    for (final handler in _handlers.values) {
      if (handler._isAffectedByChange(change)) {
        handler.invalidateCache();
      } else {
        handler._updateCachedVersion();
      }
    }

    _emitUpdate([change]);
  }

  /// Register a [SnapshotProvider]
  void registerHandler(Handler<dynamic> handler) {
    if (_handlers.containsKey(handler.id)) {
      throw HandlerAlreadyRegisteredException(
        'Handler with ID ${handler.id} already registered',
      );
    }
    _handlers[handler.id] = handler;
    handler._document = this;
  }

  /// It represents the **latest operation for each peer** of this document
  VersionVector getVersionVector() {
    if (_lastSnapshot != null) {
      return _dag.versionVector.merged(_lastSnapshot!.versionVector);
    }
    return _dag.versionVector;
  }

  /// Creates a new [Change] from the given [operation]
  Change _changeFromOp(
    Operation operation, {
    int? physicalTime,
  }) {
    final pt = physicalTime ?? DateTime.now().millisecondsSinceEpoch;
    _clock.localEvent(pt);

    final id = OperationId(_peerId, _clock.copy());
    final deps = _dag.frontiers;

    return Change(
      id: id,
      deps: deps,
      author: _peerId,
      operation: operation,
    );
  }

  /// Creates a new [Change] with the given [operation]
  ///
  /// The [Change] is automatically applied to this document.
  ///
  /// Subscribers are notified about the change only on transaction commit.
  Change createChange(
    Operation operation, {
    int? physicalTime,
  }) {
    final change = _changeFromOp(operation, physicalTime: physicalTime);
    final applied = _internalApplyChange(change);

    if (applied) {
      _reactToAppliedExternalChange(change);
    }

    return change;
  }

  /// Registers an [Operation] to this document.
  ///
  /// If there isn't a transaction an implicit transaction is opened
  ///
  /// Else the operation is added to the current transaction.
  void registerOperation(Operation operation) {
    final openedImplicitTransaction = !isInTransaction;

    try {
      if (openedImplicitTransaction) {
        _transactionManager.begin();
      }

      _transactionManager.handleOperation(operation);

      final handler = _handlers[operation.id];
      if (handler != null) {
        handler._internalIncrementCachedState(operation: operation);
      }
    } finally {
      if (openedImplicitTransaction) {
        _transactionManager.commit();
      }
    }
  }

  /// Applies a [Change] to this document
  bool _internalApplyChange(Change change) {
    // Check if the change already exists
    if (_changeStore.containsChange(change.id)) {
      return false;
    }

    // Check if the change is causally ready
    if (!_dag.isReady(change.deps)) {
      throw CausallyNotReadyException(
        'Change is not causally ready: ${change.id}',
      );
    }

    // Add the change to the store
    _changeStore.addChange(change);
    devtools.postChangedEvent(this);

    // Add the change to the DAG
    _dag.addNode(change.id, change.deps);

    // Update the clock only for remote changes
    if (change.author != _peerId) {
      _clock.receiveEvent(
        DateTime.now().millisecondsSinceEpoch,
        change.hlc,
      );
    }

    return true;
  }

  /// Applies a [Change] to this document
  ///
  /// The [Change] must be causally ready (all its dependencies must exist
  /// in the DAG).
  /// Returns `true` if the [Change] was applied, `false` if it already existed.
  bool applyChange(Change change) {
    final applied = _internalApplyChange(change);
    if (applied) {
      _reactToAppliedExternalChange(change);
    }
    return applied;
  }

  /// Takes a snapshot of the document, compacting its history.
  ///
  /// This operation captures the current state of the document,
  /// represented by its version (frontiers).
  /// [Change]s that are causally included in this version are removed from the
  /// internal [ChangeStore],
  /// effectively pruning the history up to the snapshot point.
  /// The internal [DAG] is also updated.
  /// Use [Snapshot]s to reduce memory usage and
  /// improve performance for long-lived documents.
  ///
  /// Returns a [Snapshot] representing the document's
  /// state at the current version.
  Snapshot takeSnapshot() {
    final state = <String, dynamic>{};
    for (final provider in _handlers.values) {
      state[provider.id] = provider.getSnapshotState();
    }
    final snapshot = Snapshot.create(
      versionVector: getVersionVector(),
      data: state,
    );

    _prune(snapshot.versionVector);

    _lastSnapshot = snapshot;
    return snapshot;
  }

  /// Import [Snapshot]
  ///
  /// Returns true if the snapshot was applied.
  ///
  /// [snapshot] is applied only if it is newer than document version.
  /// Use [shouldApplySnapshot] to check if the snapshot should be applied.
  bool importSnapshot(Snapshot snapshot) {
    if (shouldApplySnapshot(snapshot)) {
      _prune(snapshot.versionVector);

      _lastSnapshot = snapshot;

      _invalidateHandlers();
      _emitUpdate();
      return true;
    }

    return false;
  }

  /// Merges a [Snapshot] with the current snapshot
  ///
  /// This operation is always successful, even if the snapshot is older than
  /// the current snapshot.
  void mergeSnapshot(Snapshot snapshot) {
    if (_lastSnapshot == null) {
      _lastSnapshot = snapshot;
    } else {
      _lastSnapshot = _lastSnapshot!.merged(snapshot);
    }

    _prune(_lastSnapshot!.versionVector);
    _invalidateHandlers();
    _emitUpdate();
  }

  /// Whether the given [snapshot] should be applied.
  ///
  /// Returns `true` if the snapshot can be applied to the document.
  bool shouldApplySnapshot(Snapshot snapshot) {
    if (isEmpty) {
      return true;
    }

    return snapshot.versionVector
        .isStrictlyNewerOrEqualThan(getVersionVector());
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
  /// [snapshot] is applied only if it is newer than document version
  /// (snapshot is imported using [importSnapshot]),
  /// also [changes] are ignored if [snapshot] is not imported.
  ///
  /// If [merge] is `true`, [snapshot] is merged with the current snapshot
  /// (snapshot is imported using [mergeSnapshot])
  /// and [changes] are applied to the merged snapshot.
  ///
  /// For more details:
  /// - `merge`: `true` --> [mergeSnapshot] is called before [importChanges]
  /// - `merge`: `false` --> [importSnapshot] is called before [importChanges]
  int import({
    Snapshot? snapshot,
    List<Change>? changes,
    bool merge = false,
  }) {
    if (snapshot == null && changes == null) {
      return 0;
    }

    final changesToImport = changes ?? <Change>[];

    if (snapshot == null) {
      return importChanges(changesToImport);
    }

    if (merge) {
      mergeSnapshot(snapshot);
      return importChanges(changesToImport);
    }

    final imported = importSnapshot(snapshot);
    if (!imported) {
      return -1;
    }
    return importChanges(changesToImport);
  }

  /// Exports [Change]s from a specific version
  ///
  /// Returns a list of [Change]s that are not ancestors of the given version.
  /// If version is empty, returns all [Change]s.
  List<Change> exportChanges({Set<OperationId>? from}) {
    return _changeStore.exportChanges(from ?? {}, _dag);
  }

  /// Exports [Change]s that are newer than the provided [versionVector].
  ///
  /// A change is considered newer if its clock is strictly greater than the
  /// clock in the provided version vector for the same peer, or if the peer is
  /// not present in the provided vector.
  List<Change> exportChangesNewerThan(VersionVector versionVector) {
    return _changeStore.exportChangesNewerThan(versionVector);
  }

  /// Exports [Change]s as a binary format
  ///
  /// Returns a binary representation of the [Change]s
  /// that can be imported by another document.
  List<int> binaryExportChanges({Set<OperationId>? from}) {
    final changes = exportChanges(from: from);
    final jsonChanges = changes.map((c) => c.toJson()).toList();
    return utf8.encode(jsonEncode(jsonChanges));
  }

  /// Imports [Change]s from a binary format
  ///
  /// Returns the number of [Change]s that were applied.
  int binaryImportChanges(List<int> data) {
    final jsonStr = utf8.decode(data);
    final jsonList = jsonDecode(jsonStr) as List;
    final changes = jsonList
        .map((j) => Change.fromJson(j as Map<String, dynamic>))
        .toList();

    return importChanges(changes);
  }

  /// Imports [Change]s from another document
  ///
  /// Returns the number of [Change]s that were applied.
  int importChanges(List<Change> changes) {
    // Sort changes topologically
    final sorted = _topologicalSort(_neverReceived(changes));

    // Apply changes
    var applied = 0;
    for (final change in sorted) {
      try {
        if (_internalApplyChange(change)) {
          // TODO(mattia): set the handler affected by the change
          applied++;
        }
      } catch (e) {
        // Skip changes that can't be applied
      }
    }

    if (applied > 0) {
      // TODO(mattia): invalidate only handlers that are affected by the changes
      _invalidateHandlers();
      _emitUpdate();
    }

    return applied;
  }

  /// Prunes the DAG and the change store up to the given version.
  void _prune(VersionVector version) {
    _dag.prune(version);
    _changeStore.prune(version);
  }

  /// Emits that the document state has made an update
  /// to be notified by listeners.
  ///
  /// If a transaction is active, the update
  /// is marked as pending; otherwise it is emitted immediately.
  ///
  /// Every [CRDTDocument] must call [_emitUpdate] when something happens,
  /// the only way to **directly** notify listeners
  /// is using the [_transactionManager] callbacks.
  void _emitUpdate([List<Change>? changes]) {
    if (changes != null) {
      _transactionManager.handleAppliedChanges(changes);
    } else {
      _transactionManager.requestUpdate();
    }
  }

  /// Returns a list of [Change]s never received from this document:
  /// - the clock of the change is greater than the clock of the version vector
  /// - the change is not in the version vector
  List<Change> _neverReceived(List<Change> changes) {
    final versionVector = getVersionVector();
    final newChanges = <Change>[];

    for (final change in changes) {
      final clock = versionVector[change.id.peerId];
      if (clock == null || change.hlc.compareTo(clock) > 0) {
        newChanges.add(change);
      }
    }

    return newChanges;
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
    final queue =
        changes.where((c) => inDegree[c.id] == 0).map((c) => c.id).toList();

    while (queue.isNotEmpty) {
      final id = queue.removeAt(0);
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

  /// Invalidates the cache of all handlers
  void _invalidateHandlers() {
    for (final handler in _handlers.values) {
      handler.invalidateCache();
    }
  }

  /// Runs [action] within a transaction, committing at the end.
  ///
  /// Nested transactions are supported and will only flush once the outermost
  /// transaction is committed.
  T runInTransaction<T>(T Function() action) {
    return _transactionManager.run<T>(action);
  }

  /// Returns a string representation of this document
  @override
  String toString() {
    return 'CRDTDocument(peerId: $_peerId, changes: '
        '${_changeStore.changeCount}, version: ${version.length} frontiers)';
  }

  /// Disposes of the document
  void dispose() {
    _localChangesController.close();
    _updatesController.close();
  }
}

/// A consumer that can consume a CRDTDocument
mixin DocumentConsumer {
  /// The document that `this` can consume
  late final CRDTDocument _document;

  /// The unique identifier for `this` consumer
  String get id;
}

/// A provider that can provide a cacheable state of a [CRDTDocument]
///
/// [T] is the type of the cached state of the handler.
/// The handler state can be whatever the handler needs it to be
/// to perform better. There is no binding with the `handler.value`
/// or `getSnapshotState`.
mixin CacheableStateProvider<T> on DocumentConsumer {
  @override
  String get id;

  /// The version at witch the cached state is still valid
  Set<OperationId>? _cachedVersion;

  /// The cached state of the handler
  T? _cachedState;

  /// Whether to use incremental cache update
  bool useIncrementalCacheUpdate = true;

  /// Updates the cached version with the current version of the document
  void _updateCachedVersion() {
    _cachedVersion = Set.from(_document.version);
  }

  /// Updates the cached state
  void updateCachedState(T newState) {
    _cachedState = newState;
    _updateCachedVersion();
  }

  void _internalIncrementCachedState({required Operation operation}) {
    if (!useIncrementalCacheUpdate) {
      invalidateCache();
      return;
    }

    final state = _cachedState;
    if (state == null) {
      return;
    }

    final newState = incrementCachedState(
      operation: operation,
      state: state,
    );

    if (newState == null) {
      invalidateCache();
      return;
    }

    updateCachedState(newState);
  }

  /// When the document receives an operation and a change is applied
  /// anyone using [CacheableStateProvider] is allowed to
  /// increment the cached state.
  ///
  /// Use the [operation] to increment the current [state]
  T? incrementCachedState({
    required Operation operation,
    required T state,
  }) {
    return null;
  }

  /// Invalidates the cached state
  ///
  /// [CRDTDocument] automatically invalidates
  /// the cache when an external effect happens (import, export, etc.).
  void invalidateCache() {
    _cachedState = null;
    _cachedVersion = null;
  }

  /// Returns the cached state
  T? get cachedState {
    if (_cachedState != null && setEquals(_cachedVersion, _document.version)) {
      return _cachedState;
    }

    return null;
  }
}

/// A provider that can provide a snapshot of the state of a [CRDTDocument]
mixin SnapshotProvider on DocumentConsumer {
  @override
  String get id;

  /// Returns the current state of the provider
  dynamic getSnapshotState();

  /// Return the last snapshot of the document
  dynamic lastSnapshot() {
    return _document._lastSnapshot?.data[id];
  }
}

/// Helper extensions for [Handler]
extension _HandlerHelper on Handler<dynamic> {
  /// Whether the handler is affected by the given [change]
  bool _isAffectedByChange(Change change) {
    final id = Operation.handlerIdFrom(payload: change.payload);
    return id == this.id;
  }
}
