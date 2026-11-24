// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:collection';

import 'package:crdt_lf_devtools_extension/src/application/changes/list_views.dart';
import 'package:equatable/equatable.dart';

/// A change as the lane graph sees it: its author and the authors of its
/// dependencies.
typedef GraphNode = ({String author, Iterable<String> depAuthors});

/// The lane graph of one row of the change list.
class RowGraph extends Equatable {
  const RowGraph({
    required this.lane,
    required this.activeMask,
    required this.mergesFrom,
  });

  /// The lane of the change of this row.
  final int lane;

  /// The active lanes as bits: bit `n` is lane `n`.
  final int activeMask;

  /// The lanes of the dependencies that are on another lane, sorted.
  final List<int> mergesFrom;

  /// Whether [lane] has a change at or before this row, and one at or after
  /// it.
  bool isActive(int lane) => activeMask & (1 << lane) != 0;

  /// The active lanes, sorted.
  List<int> get active => [
    for (var lane = 0; lane < LaneGraph.maxLanes; lane++)
      if (isActive(lane)) lane,
  ];

  @override
  List<Object?> get props => [lane, activeMask, mergesFrom];
}

/// The lanes of a change list, one per author, and one [RowGraph] per row.
class LaneGraph {
  /// Builds the graph of [nodes], given in replay order.
  ///
  /// Lanes are numbered in the order the authors first appear. From the
  /// author [maxLanes] on, every author shares the last lane. A dependency
  /// whose author has no change before it (a pruned one) draws no merge.
  factory LaneGraph(List<GraphNode> nodes) => empty.extend(nodes);

  const LaneGraph._(
    this._lanes,
    this._length,
    this._peerCount,
    this._first,
    this._last,
  );

  /// The graph of no change.
  static const LaneGraph empty = LaneGraph._(null, 0, 0, [], []);

  /// The most lanes a graph draws.
  static const int maxLanes = 6;

  // Shared with the graphs built from this one.
  final _Lanes? _lanes;

  final int _length;

  final int _peerCount;

  final List<int> _first;

  final List<int> _last;

  /// This graph with [nodes] after its own, in replay order; this graph
  /// stays as it is.
  LaneGraph extend(List<GraphNode> nodes) => replaceFrom(_length, nodes);

  /// This graph with its rows from [from] on replaced by [nodes], in replay
  /// order.
  ///
  /// Below its length, it can change the rows of this graph and of the
  /// graphs this one was built from: call it on the last graph only.
  LaneGraph replaceFrom(int from, List<GraphNode> nodes) {
    var lanes = _lanes;
    if (lanes == null || lanes.lanes.length != _length) {
      lanes = _Lanes.copyOf(this);
    }
    lanes.truncate(from);
    nodes.forEach(lanes.add);
    return LaneGraph._(
      lanes,
      lanes.lanes.length,
      lanes.peers.length,
      List.unmodifiable([for (final rows in lanes.rowsByLane) rows.firstOr]),
      List.unmodifiable([for (final rows in lanes.rowsByLane) rows.lastOr]),
    );
  }

  /// The authors in the order they first appear; author `n` is on lane `n`,
  /// up to the last lane.
  List<String> get peers => switch (_lanes) {
    null => const [],
    final lanes => PrefixView(lanes.peers, _peerCount),
  };

  /// One graph per row, in replay order.
  List<RowGraph> get rows => _Rows(this);

  /// The number of lanes drawn.
  int get laneCount => _peerCount < maxLanes ? _peerCount : maxLanes;

  /// Whether the last lane holds more than one author.
  bool get sharedLastLane => _peerCount > maxLanes;

  RowGraph _row(int row) {
    var mask = 0;
    for (var lane = 0; lane < maxLanes; lane++) {
      if (_first[lane] >= 0 && _first[lane] <= row && row <= _last[lane]) {
        mask |= 1 << lane;
      }
    }
    return RowGraph(
      lane: _lanes!.lanes[row],
      activeMask: mask,
      mergesFrom: _lanes.merges[row],
    );
  }
}

class _Rows extends ListBase<RowGraph> {
  _Rows(this._graph);

  final LaneGraph _graph;

  @override
  int get length => _graph._length;

  @override
  set length(int _) => throw UnsupportedError('A read-only list');

  @override
  RowGraph operator [](int index) {
    RangeError.checkValidIndex(index, this, null, length);
    return _graph._row(index);
  }

  @override
  void operator []=(int index, RowGraph value) =>
      throw UnsupportedError('A read-only list');
}

class _Lanes {
  _Lanes()
    : laneOf = <String, int>{},
      firstRowOf = <String, int>{},
      peers = <String>[],
      lanes = <int>[],
      merges = <List<int>>[],
      rowsByLane = [for (var i = 0; i < LaneGraph.maxLanes; i++) <int>[]];

  factory _Lanes.copyOf(LaneGraph graph) {
    final copy = _Lanes();
    final source = graph._lanes;
    if (source == null) return copy;
    for (final peer in source.peers.take(graph._peerCount)) {
      copy.peers.add(peer);
      copy.laneOf[peer] = source.laneOf[peer]!;
      copy.firstRowOf[peer] = source.firstRowOf[peer]!;
    }
    for (var row = 0; row < graph._length; row++) {
      final lane = source.lanes[row];
      copy.lanes.add(lane);
      copy.merges.add(source.merges[row]);
      copy.rowsByLane[lane].add(row);
    }
    return copy;
  }

  final Map<String, int> laneOf;

  final Map<String, int> firstRowOf;

  final List<String> peers;

  final List<int> lanes;

  final List<List<int>> merges;

  final List<List<int>> rowsByLane;

  void add(GraphNode node) {
    final row = lanes.length;
    final lane = laneOf[node.author] ??= _newLane(node.author, row);
    lanes.add(lane);
    rowsByLane[lane].add(row);
    final from = <int>{
      for (final author in node.depAuthors)
        if (laneOf[author] case final l? when l != lane) l,
    };
    merges.add(
      from.isEmpty ? const [] : List.unmodifiable(from.toList()..sort()),
    );
  }

  /// Drops the rows from [from] on, and the authors they brought.
  void truncate(int from) {
    if (from >= lanes.length) return;
    lanes.length = from;
    merges.length = from;
    for (final rows in rowsByLane) {
      while (rows.isNotEmpty && rows.last >= from) {
        rows.removeLast();
      }
    }
    // An author's first row grows with its place in `peers`.
    while (peers.isNotEmpty && firstRowOf[peers.last]! >= from) {
      final peer = peers.removeLast();
      laneOf.remove(peer);
      firstRowOf.remove(peer);
    }
  }

  int _newLane(String author, int row) {
    peers.add(author);
    firstRowOf[author] = row;
    return peers.length < LaneGraph.maxLanes
        ? peers.length - 1
        : LaneGraph.maxLanes - 1;
  }
}

extension on List<int> {
  int get firstOr => isEmpty ? -1 : first;

  int get lastOr => isEmpty ? -1 : last;
}
