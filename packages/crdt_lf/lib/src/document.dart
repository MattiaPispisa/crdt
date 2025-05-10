import 'dart:async';
import 'dart:convert';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/devtools/devtools.dart' as devtools;
import 'package:hlc_dart/hlc_dart.dart';

/// CRDT Document implementation
///
/// A CRDTDocument is the main entry point for the CRDT system.
/// It manages the DAG, ChangeStore, and provides methods for creating,
/// applying, exporting, and importing changes.
class CRDTDocument {
  /// Creates a new [CRDTDocument] with the given [peerId]
  CRDTDocument({
    PeerId? peerId,
  })  : _dag = DAG.empty(),
        _changeStore = ChangeStore.empty(),
        _peerId = peerId ?? PeerId.generate(),
        _clock = HybridLogicalClock.initialize(),
        _localChangesController = StreamController<Change>.broadcast(),
        _handlers = {} {
    devtools.handleCreated(this);
  }

  /// The DAG that tracks causal relationships between operations
  final DAG _dag;

  /// The store for changes
  final ChangeStore _changeStore;

  /// The ID of the peer that owns this document
  final PeerId _peerId;

  /// The hybrid logical clock for this document
  final HybridLogicalClock _clock;

  /// Gets the peer ID of this document
  PeerId get peerId => _peerId;

  /// Gets the current timestamp of this document
  HybridLogicalClock get hlc => _clock.copy();

  /// Gets the current version of this document (the frontiers of the DAG)
  Set<OperationId> get version => _dag.frontiers;

  /// A stream controller for locally generated changes.
  final StreamController<Change> _localChangesController;

  /// A stream that emits [Change]s created locally by this document.
  Stream<Change> get localChanges => _localChangesController.stream;

  /// The registered snapshot providers
  final Map<String, Handler<dynamic>> _handlers;

  /// The last snapshot of this document
  Snapshot? _lastSnapshot;

  /// Whether this document is empty.
  /// (no changes and no snapshot)
  bool get isEmpty => _changeStore.changeCount == 0 && _lastSnapshot == null;

  /// Register a [SnapshotProvider]
  void registerHandler(Handler<dynamic> handler) {
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

  /// Creates a new [Change] with the given [operation]
  ///
  /// The [Change] is automatically applied to this document.
  Change createChange(
    Operation operation, {
    int? physicalTime,
  }) {
    final pt = physicalTime ?? DateTime.now().millisecondsSinceEpoch;
    _clock.localEvent(pt);

    final id = OperationId(_peerId, _clock.copy());
    final deps = _dag.frontiers;

    final change = Change(
      id: id,
      deps: deps,
      hlc: _clock.copy(),
      author: _peerId,
      operation: operation,
    );

    final applied = applyChange(change);
    if (applied) {
      _localChangesController.add(change);
    }
    return change;
  }

  /// Applies a [Change] to this document
  ///
  /// The [Change] must be causally ready (all its dependencies must exist
  /// in the DAG).
  /// Returns `true` if the [Change] was applied, `false` if it already existed.
  bool applyChange(Change change) {
    // Check if the change already exists
    if (_changeStore.containsChange(change.id)) {
      return false;
    }

    // Check if the change is causally ready
    if (!_dag.isReady(change.deps)) {
      throw StateError('Change is not causally ready: ${change.id}');
    }

    // Add the change to the store
    _changeStore.addChange(change);
    devtools.postChangedEvent(this);

    // Add the change to the DAG
    _dag.addNode(change.id, change.deps);

    // Update the clock
    _clock.receiveEvent(
      DateTime.now().millisecondsSinceEpoch,
      change.hlc,
    );

    return true;
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

      for (final provider in _handlers.values) {
        provider.invalidateCache();
      }

      return true;
    }

    return false;
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

  /// Exports [Change]s from a specific version
  ///
  /// Returns a list of [Change]s that are not ancestors of the given version.
  /// If version is empty, returns all [Change]s.
  List<Change> exportChanges({Set<OperationId>? from}) {
    return _changeStore.exportChanges(from ?? {}, _dag);
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
        if (applyChange(change)) {
          applied++;
        }
      } catch (e) {
        // Skip changes that can't be applied
      }
    }

    return applied;
  }

  void _prune(VersionVector version) {
    _dag.prune(version);
    _changeStore.prune(version);
  }

  /// Returns a list of [Change]s never received from this document:
  /// - the clock of the change is greater than the clock of the version vector
  /// - the change is not in the version vector
  List<Change> _neverReceived(List<Change> changes) {
    final versionVector = getVersionVector();
    final newChanges = <Change>[];

    for (final change in changes) {
      final clock = versionVector[change.id.peerId];
      if (clock == null || change.id.hlc.compareTo(clock) > 0) {
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
    // Build a graph of dependencies
    final graph = <OperationId, Set<OperationId>>{};
    final inDegree = <OperationId, int>{};

    for (final change in changes) {
      graph[change.id] = {};
      inDegree[change.id] = 0;
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

    // Perform topological sort
    final queue =
        changes.where((c) => inDegree[c.id] == 0).map((c) => c.id).toList();
    final result = <Change>[];

    while (queue.isNotEmpty) {
      final id = queue.removeAt(0);
      // TODO(mattia): where is expensive
      final change = changes.firstWhere((c) => c.id == id);
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
      throw StateError('Cycle detected in changes');
    }

    return result;
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
  }
}

/// A provider that can provide a snapshot of the state of a CRDT
mixin SnapshotProvider {
  /// The unique identifier for this provider
  String get id;

  CRDTDocument? _document;

  /// Returns the current state of the provider
  dynamic getSnapshotState();

  /// Return the last snapshot of the document
  dynamic lastSnapshot() {
    return _document?._lastSnapshot?.data[id];
  }
}
