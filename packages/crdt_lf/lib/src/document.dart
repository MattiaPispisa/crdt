import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/compound/compound.dart';
import 'package:crdt_lf/src/devtools/devtools.dart' as devtools;
import 'package:crdt_lf/src/transaction/transaction_manager.dart';
import 'package:hlc_dart/hlc_dart.dart';

/// Defines the foundational contract for a CRDT document.
///
/// This abstract class serves as the common interfaces between
/// the live [CRDTDocument] and the static read-only document.
abstract class BaseCRDTDocument {
  bool _isDisposed = false;

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
        _documentId = documentId ?? PeerId.generate().toString(),
        _clock = initialClock ?? HybridLogicalClock.initialize(),
        _localChangesController = StreamController<Change>.broadcast(),
        _updatesController = StreamController<void>.broadcast(),
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

  /// Prepares the system to perform a mutation.
  ///
  /// What this currently does:
  /// - updates the document's clock
  ///
  /// Call this only when you intend to execute a causal operation,
  /// not just to update the clock for timekeeping.
  ///
  /// Examples of causal operations:
  /// - creating a tag that references a [HybridLogicalClock]
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

  /// A stream controller for locally generated changes.
  final StreamController<Change> _localChangesController;

  /// A stream that emits [Change]s created locally by this document.
  Stream<Change> get localChanges => _localChangesController.stream;

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
  void _updateCacheWithAppliedExternalChange(Change change) {
    for (final handler in _handlers.values) {
      if (handler._isAffectedByChange(change)) {
        handler.invalidateCache();
      } else {
        handler._updateCachedVersion();
      }
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

  /// Creates a new [Change] from the given [operation]
  Change _changeFromOp(
    Operation operation, {
    int? physicalTime,
  }) {
    _tickClock(physicalTime: physicalTime);

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
    _ensureNotDisposed('createChange');

    final change = _changeFromOp(operation, physicalTime: physicalTime);
    final applied = _internalApplyChange(change);

    if (applied) {
      _updateCacheWithAppliedExternalChange(change);
      _emitUpdate([change]);
    }

    return change;
  }

  @override
  void registerOperation(Operation operation) {
    _ensureNotDisposed('registerOperation');

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
  bool applyChange(Change change) {
    _ensureNotDisposed('applyChange');

    final applied = _internalApplyChange(change);
    if (applied) {
      _updateCacheWithAppliedExternalChange(change);
      _emitUpdate([change]);
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

    final state = <String, Uint8List>{};
    for (final provider in _handlers.values) {
      state[provider.id] = provider.getSnapshotState();
    }
    final snapshot = Snapshot.create(
      versionVector: getVersionVector(),
      data: state,
    );

    if (pruneHistory) {
      _prune(snapshot.versionVector);
    }

    _lastSnapshot = snapshot;
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
      if (pruneHistory) {
        _prune(snapshot.versionVector);
      }

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

    if (pruneHistory) {
      _prune(_lastSnapshot!.versionVector);
    }
    _invalidateHandlers();
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
  }) {
    _ensureNotDisposed('import');

    if (snapshot == null && changes == null) {
      return 0;
    }

    final changesToImport = changes ?? <Change>[];

    if (snapshot == null) {
      return importChanges(changesToImport);
    }

    if (merge) {
      mergeSnapshot(snapshot, pruneHistory: pruneHistory);
      return importChanges(changesToImport);
    }

    final imported = importSnapshot(snapshot, pruneHistory: pruneHistory);
    if (!imported) {
      return -1;
    }
    return importChanges(changesToImport);
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
    final changes = exportChanges(from: from);
    final blobs = <Uint8List>[];

    for (final change in changes) {
      final out = BytesBuilder(copy: false);
      UVarint.write(change.depsCount, out);
      out.add(change.bytes);
      blobs.add(out.toBytes());
    }

    return ChangeCodec.encodeBlobs(blobs);
  }

  /// Imports [Change]s from the compact binary format.
  ///
  /// Returns the number of [Change]s that were applied.
  int binaryImportChanges(Uint8List data) {
    _ensureNotDisposed('binaryImportChanges');

    final blobs = ChangeCodec.decodeBlobs(data);
    final changes = <Change>[];

    for (final blob in blobs) {
      final depsCountRec = UVarint.read(blob, offset: 0);
      final depsCount = depsCountRec.value;
      final bytes = Uint8List.sublistView(blob, depsCountRec.nextOffset);

      if (bytes.length < OperationId.byteLength) {
        throw const FormatException('Truncated change bytes');
      }

      final id = OperationId.fromUint8List(bytes);
      final deps = <OperationId>{};

      var cursor = OperationId.byteLength;
      for (var i = 0; i < depsCount; i += 1) {
        if (cursor + OperationId.byteLength > bytes.length) {
          throw const FormatException('Truncated change dependencies');
        }
        deps.add(OperationId.fromUint8List(bytes, offset: cursor));
        cursor += OperationId.byteLength;
      }

      final payloadBytes = Uint8List.sublistView(bytes, cursor);
      changes.add(
        Change.fromPayloadBytes(
          id: id,
          deps: deps,
          author: id.peerId,
          payloadBytes: payloadBytes,
        ),
      );
    }

    return importChanges(changes);
  }

  /// Imports [Change]s from another document
  ///
  /// Returns the number of [Change]s that were applied.
  int importChanges(List<Change> changes) {
    _ensureNotDisposed('importChanges');

    // Sort changes topologically
    final sorted = _topologicalSort(_neverReceived(changes));

    // Apply changes
    final changedApplied = <Change>[];
    for (final change in sorted) {
      try {
        if (_internalApplyChange(change)) {
          _updateCacheWithAppliedExternalChange(change);
          changedApplied.add(change);
        }
      } catch (e) {
        // Skip changes that can't be applied
      }
    }

    if (changedApplied.isNotEmpty) {
      _emitUpdate();
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
      final clock = versionVector[change.author];
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
    _ensureNotDisposed('runInTransaction');

    return _transactionManager.run<T>(action);
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
      final snapshotClock = versionVector[dep.peerId];
      if (snapshotClock == null || dep.hlc.compareTo(snapshotClock) > 0) {
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

    _localChangesController.close();
    _updatesController.close();
    super.dispose();
  }
}

class _CRDTStaticProxyDocument extends BaseCRDTDocument {
  _CRDTStaticProxyDocument({
    required String documentId,
    required HybridLogicalClock hlc,
    required PeerId peerId,
    required List<Change> frozenChanges,
    required List<Set<OperationId>> historyVersions,
    required int visibleCount,
    required Snapshot? lastSnapshot,
    required Map<String, Handler<dynamic>> handlers,
  })  : _documentId = documentId,
        _hlc = hlc,
        _peerId = peerId,
        _frozenChanges = frozenChanges,
        _historyVersions = historyVersions,
        _visibleCount = visibleCount,
        _lastSnapshot = lastSnapshot,
        _handlers = handlers;

  final String _documentId;

  final HybridLogicalClock _hlc;

  final PeerId _peerId;

  final List<Change> _frozenChanges;

  final List<Set<OperationId>> _historyVersions;

  int _visibleCount;

  @override
  String get documentId => _documentId;

  @override
  HybridLogicalClock get hlc => _hlc;

  @override
  PeerId get peerId => _peerId;

  @override
  final Snapshot? _lastSnapshot;

  @override
  final Map<String, Handler<dynamic>> _handlers;

  @override
  void registerOperation(Operation operation) {
    throw const ReadOnlyDocumentException('registerOperation');
  }

  @override
  void prepareMutation() {
    throw const ReadOnlyDocumentException('prepareMutation');
  }

  @override
  Set<OperationId> get version {
    if (_visibleCount == 0) {
      return {};
    }
    return _historyVersions[_visibleCount - 1];
  }

  @override
  List<Change> exportChanges({
    Set<OperationId>? from,
    VersionVector? fromVersionVector,
  }) {
    var changes = _frozenChanges.sublist(0, _visibleCount);

    if (fromVersionVector != null && _lastSnapshot != null) {
      changes = changes.newerThan(_lastSnapshot!.versionVector).toList();
    }

    return changes;
  }
}

/// {@template history_session}
/// An interactive controller for navigating the history of a [CRDTDocument].
///
/// A [HistorySession] creates a frozen, immutable view of a [CRDTDocument]
/// as the moment of instantiation. It allows "Time tavel" functionality by
/// moving a temporal cursor back and forth through the [Change]s.
///
/// ```dart
/// final document = CRDTDocument();
/// final listHandler = CRDTListHandler<String>(document, 'list');
/// listHandler
///   ..insert(0, 'Hello')
///   ..insert(1, 'World')
///   ..insert(2, 'Dart');
///
/// final historySession = document.toTimeTravel();
/// final viewListHandler = historySession.getHandler(
///   (doc) => CRDTListHandler<String>(doc, 'list'),
/// );
///
/// print(viewListHandler.value); // ['Hello', 'World', 'Dart']
///
/// historySession.previous();
/// print(viewListHandler.value); // ['Hello', 'World']
///
/// historySession.next();
/// print(viewListHandler.value); // ['Hello', 'World', 'Dart']
/// ```
/// {@endtemplate}
class HistorySession {
  HistorySession._({
    required int cursor,
    required _CRDTStaticProxyDocument document,
    required this.length,
  })  : _document = document,
        _cursor = cursor,
        _cursorController = StreamController<int>.broadcast();

  factory HistorySession._fromLiveDocument(
    BaseCRDTDocument document,
  ) {
    final changes = document.exportChanges().sorted();

    final historyVersions = <Set<OperationId>>[];
    final tempFrontiers = Frontiers();

    for (final change in changes) {
      tempFrontiers.update(
        newOperationId: change.id,
        oldDependencies: change.deps,
      );

      historyVersions.add(tempFrontiers.get());
    }

    final cursor = changes.length;

    return HistorySession._(
      cursor: cursor,
      length: cursor,
      document: _CRDTStaticProxyDocument(
        documentId: document.documentId,
        hlc: document.hlc,
        peerId: document.peerId,
        frozenChanges: changes,
        historyVersions: historyVersions,
        visibleCount: cursor,
        lastSnapshot: document._lastSnapshot,
        handlers: {},
      ),
    );
  }

  final _CRDTStaticProxyDocument _document;
  int _cursor;
  final StreamController<int> _cursorController;

  /// The total number of changes available in this history session.
  final int length;

  /// The stream of cursor position updates.
  ///
  /// Emits the new cursor index whenever
  /// [next], [previous], or [jump] is called.
  Stream<int> get cursorStream => _cursorController.stream;

  /// The current position of the temporal cursor.
  ///
  /// Represents the number of changes currently applied to the view.
  /// - 0: Initial state (snapshot only).
  /// - [length]: The full state at the time the session was created.
  int get cursor => _cursor;

  /// Whether the cursor can move forward (Redo).
  bool get canNext => _cursor < length;

  /// Whether the cursor can move backward (Undo).
  bool get canPrevious => _cursor > 0;

  /// Factory method to instantiate a CRDT Handler linked
  /// to this history session.
  ///
  /// [Handler]s bound to the history session can only view their states,
  /// on write operations (example [BaseCRDTDocument.registerOperation]) a
  /// [ReadOnlyDocumentException] is thrown
  H getHandler<H extends Handler<T>, T>(
    H Function(BaseCRDTDocument document) factory,
  ) {
    return factory(_document);
  }

  /// Advances the cursor by one step.
  ///
  /// Does nothing if [canNext] is false.
  void next() => jump(_cursor + 1);

  /// Moves the cursor back by one step.
  ///
  /// Does nothing if [canPrevious] if false.
  void previous() => jump(_cursor - 1);

  /// Jumps immediately to a specific point in history.
  ///
  /// [cursor] must be between 0 and [length] (inclusive).
  /// Does nothing if cursor remains the same.
  void jump(int cursor) {
    if (cursor < 0 || cursor > length) {
      return;
    }
    if (cursor == _cursor) {
      return;
    }

    _cursor = cursor;
    _document._visibleCount = _cursor;
    _cursorController.add(_cursor);
  }

  /// Releases resources used by this session.
  void dispose() {
    _cursorController.close();
    _document.dispose();
  }
}

/// A consumer that can consume a CRDTDocument
mixin DocumentConsumer {
  /// The document that `this` can consume
  late final BaseCRDTDocument _document;

  /// The unique identifier for `this` consumer
  String get id;
}

/// Per-consumer state cache that avoids recomputing the consumer's state
/// from the full history on every read.
///
/// Two update paths:
/// - **incremental**: when a single [Operation] is applied, the cache is
///   patched via [incrementCachedState]. Hosts that can cheaply apply an
///   operation to their state override it; returning `null` means "can't
///   (or won't) update incrementally" and falls back to invalidation.
/// - **full recompute**: [cachedState] returns `null` whenever the cached
///   version no longer matches the document's current version (e.g. after
///   import, snapshot merge or prune). The host recomputes the state from
///   scratch and pushes it back via [updateCachedState].
///
/// [T] is the host's own internal representation. It has no required
/// relationship with `handler.value` or [SnapshotProvider.getSnapshotState]
/// — pick whatever shape makes recomputation cheap.
/// 
/// Set [useIncrementalCacheUpdate] to false to ignore [incrementCachedState]
mixin CacheableStateProvider<T> on DocumentConsumer {
  @override
  String get id;

  /// Document version the cached state is pinned to (`null` when no
  /// state is cached). The cache is valid only while this set equals
  /// `_document.version`.
  Set<OperationId>? _cachedVersion;

  /// The most recently cached state, or `null` if no state is cached.
  T? _cachedState;

  /// If `false`, every applied operation invalidates the cache instead of
  /// invoking [incrementCachedState]. Hosts that have no cheap incremental
  /// path may set this to `false` to skip the hook entirely; the default
  /// `true` lets each operation try the incremental path first.
  bool useIncrementalCacheUpdate = true;

  /// Pins the cached version to the document's current version.
  void _updateCachedVersion() {
    _cachedVersion = Set.from(_document.version);
  }

  /// Replaces the cached state with [newState] and pins it to the current
  /// document version. Call this after a full recompute.
  void updateCachedState(T newState) {
    _cachedState = newState;
    _updateCachedVersion();
  }

  /// Framework hook: tries to advance the cache by a single [operation],
  /// honoring [useIncrementalCacheUpdate]. Falls back to [invalidateCache]
  /// when the host opts out, has no cached state, or cannot apply the
  /// operation incrementally.
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

  /// Applies [operation] to [state] and returns the resulting state, or
  /// `null` to opt out of incremental updates (the cache will be
  /// invalidated and recomputed on the next read).
  ///
  /// May mutate [state] in place and return it. The default implementation
  /// returns `null`, i.e. no incremental path.
  T? incrementCachedState({
    required Operation operation,
    required T state,
  }) {
    return null;
  }

  /// Drops the cached state. The framework calls this automatically when
  /// the consumer's state is no longer guaranteed to match the document
  /// (e.g. external changes imported, snapshot merged, history pruned).
  void invalidateCache() {
    _cachedState = null;
    _cachedVersion = null;
  }

  /// The cached state if it still matches the document's current version,
  /// otherwise `null` (forcing the host to recompute).
  T? get cachedState {
    if (_cachedState != null && setEquals(_cachedVersion, _document.version)) {
      return _cachedState;
    }

    return null;
  }
}

/// A provider that can provide a snapshot of the state of a [CRDTDocument]
///
/// Snapshot state is now a binary blob owned by the consumer. The framework
/// only frames each blob with a length prefix inside [Snapshot]; the encoding
/// and decoding of the blob's contents is entirely up to the consumer.
mixin SnapshotProvider on DocumentConsumer {
  @override
  String get id;

  /// Encodes the consumer's current state to a binary blob.
  ///
  /// The blob is opaque to `crdt_lf` itself and will be returned verbatim
  /// by [lastSnapshot] when the consumer needs to reconstruct its state.
  Uint8List getSnapshotState();

  /// Returns the last snapshot bytes for this consumer (the value previously
  /// produced by [getSnapshotState]) or `null` if no snapshot is available.
  Uint8List? lastSnapshot() {
    return _document._lastSnapshot?.data[id];
  }

  /// Returns the version vector of the last snapshot for this consumer.
  VersionVector? snapshotVersionVector() {
    return _document._lastSnapshot?.versionVector;
  }
}

/// Helper extensions for [Handler]
extension _HandlerHelper on Handler<dynamic> {
  // Expando acts as a per-instance cache (weak-ref keyed map).
  // Extensions cannot declare instance fields, but an Expando on a static
  // variable gives the same semantics with no memory-leak risk.
  static final Expando<Uint8List> _prefixCache = Expando();

  /// Binary prefix for this handler's operations:
  /// [varint(typeLen)][type UTF-8][varint(idLen)][id UTF-8].
  ///
  /// Computed once and cached. Compared byte-by-byte against a change payload
  /// in [_isAffectedByChange] to avoid UTF-8 decode + String allocation on
  /// every change application.
  Uint8List get _envelopePrefix {
    return _prefixCache[this] ??= _buildPrefix();
  }

  Uint8List _buildPrefix() {
    final out = BytesBuilder(copy: false);
    final typeBytes = utf8.encode(runtimeType.toString());
    UVarint.write(typeBytes.length, out);
    out.add(typeBytes);
    final idBytes = utf8.encode(id);
    UVarint.write(idBytes.length, out);
    out.add(idBytes);
    return out.toBytes();
  }

  bool _isAffectedByChange(Change change) {
    final payload = change.payloadBytes();
    final prefix = _envelopePrefix;
    // +1 for the kind byte that follows the prefix.
    if (payload.length < prefix.length + 1) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (payload[i] != prefix[i]) return false;
    }
    return true;
  }
}
