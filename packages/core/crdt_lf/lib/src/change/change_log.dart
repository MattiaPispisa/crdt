// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:collection';

import 'package:crdt_lf/crdt_lf.dart';

/// The changes a document holds, and the causal graph between them.
///
/// A change enters only when every dependency is here, or is covered by the
/// version of the snapshot the history is replayed on.
class ChangeLog {
  /// Creates an empty log.
  ChangeLog()
      : _dag = DAG.empty(),
        _store = ChangeStore.empty();

  final DAG _dag;
  final ChangeStore _store;

  /// The ids of the changes no other change depends on.
  Set<OperationId> get frontiers => _dag.frontiers;

  /// The latest change of each peer in the log; the snapshot is not counted.
  VersionVector get versionVector => _dag.versionVector;

  /// How many changes the log holds.
  int get changeCount => _store.changeCount;

  /// Adds [change]; returns `false` when the log already holds it.
  ///
  /// A dependency missing from the log is accepted when [snapshotVersion] has
  /// seen it: a prune took it away. Throws [CausallyNotReadyException] for any
  /// other missing dependency, and then adds nothing.
  bool add(Change change, {VersionVector? snapshotVersion}) {
    if (_store.containsChangeKey(change.key)) {
      return false;
    }

    final missing = {
      for (final dep in change.deps)
        if (!_dag.containsNode(dep)) dep,
    };
    if (missing.isNotEmpty && !_coveredBy(missing, snapshotVersion)) {
      throw CausallyNotReadyException(
        'Change is not causally ready: ${change.id}',
      );
    }

    _store.addChange(change);
    _dag.addNode(change.id, change.deps.where(_dag.containsNode).toSet());
    return true;
  }

  static bool _coveredBy(
    Set<OperationId> deps,
    VersionVector? snapshotVersion,
  ) {
    if (snapshotVersion == null) {
      return false;
    }
    for (final dep in deps) {
      if (!snapshotVersion.hasSeen(dep.peerId, dep.hlc)) {
        return false;
      }
    }
    return true;
  }

  /// [changes] in an order where each change comes after its dependencies
  /// among [changes].
  ///
  /// Throws [ChangesCycleException] when [changes] depend on each other in a
  /// cycle.
  static List<Change> sortTopologically(List<Change> changes) {
    final result = <Change>[];

    if (changes.isEmpty) {
      return result;
    }

    final changeMap = <OperationId, Change>{};
    final graph = <OperationId, Set<OperationId>>{};
    final inDegree = <OperationId, int>{};

    for (final change in changes) {
      graph[change.id] = {};
      inDegree[change.id] = 0;
      changeMap[change.id] = change;
    }

    for (final change in changes) {
      for (final dep in change.deps) {
        if (graph.containsKey(dep)) {
          graph[dep]!.add(change.id);
          inDegree[change.id] = (inDegree[change.id] ?? 0) + 1;
        }
      }
    }

    final queue = ListQueue<OperationId>.of(
      changes.where((c) => inDegree[c.id] == 0).map((c) => c.id),
    );

    while (queue.isNotEmpty) {
      final id = queue.removeFirst();
      result.add(changeMap[id]!);

      for (final dependent in graph[id]!) {
        inDegree[dependent] = inDegree[dependent]! - 1;
        if (inDegree[dependent] == 0) {
          queue.add(dependent);
        }
      }
    }

    if (result.length != changes.length) {
      throw const ChangesCycleException('Cycle detected in changes');
    }

    return result;
  }

  /// Removes the changes [version] has seen.
  ///
  /// A change that stays loses its dependencies on the removed ones.
  /// [onPruned] gets the removed changes and the rewritten ones, and is called
  /// only when something was removed.
  void prune(
    VersionVector version, {
    void Function(List<Change> removed, List<Change> rewritten)? onPruned,
  }) {
    _dag.prune(version);
    _store.prune(version, onPruned: onPruned);
  }

  /// The changes after [from], or newer than [fromVersionVector]; every
  /// change when both are `null`. [fromVersionVector] wins when both are set.
  List<Change> exportChanges({
    Set<OperationId>? from,
    VersionVector? fromVersionVector,
  }) {
    if (from == null && fromVersionVector == null) {
      return _store.getAllChanges();
    }
    if (fromVersionVector != null) {
      return _store.exportChangesNewerThan(fromVersionVector);
    }
    return _store.exportChanges(from ?? const {}, _dag);
  }

  /// The changes whose clock is newer than what [versionVector] holds for
  /// their peer, or whose peer it does not hold.
  List<Change> exportChangesNewerThan(VersionVector versionVector) =>
      _store.exportChangesNewerThan(versionVector);

  /// The changes of the handler [handlerId], newer than [fromVersionVector]
  /// when it is set.
  List<Change> changesForHandler(
    String handlerId, {
    VersionVector? fromVersionVector,
  }) =>
      _store.changesForHandler(
        handlerId,
        fromVersionVector: fromVersionVector,
      );

  /// How many changes the handler [handlerId] has in the log.
  int changeCountForHandler(String handlerId) =>
      _store.changeCountForHandler(handlerId);

  /// The ids of the handlers with at least one change in the log.
  Iterable<String> get handlerIds => _store.handlerIds;
}
