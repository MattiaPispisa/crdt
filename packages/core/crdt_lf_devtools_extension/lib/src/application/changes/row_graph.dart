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

  // Shared with the graphs extended from this one, which only append.
  final _Lanes? _lanes;

  final int _length;

  final int _peerCount;

  final List<int> _first;

  final List<int> _last;

  /// This graph with [nodes] after its own, in replay order; this graph
  /// stays as it is.
  LaneGraph extend(List<GraphNode> nodes) {
    var lanes = _lanes;
    if (lanes == null || lanes.lanes.length != _length) {
      lanes = _Lanes.copyOf(this);
    }
    nodes.forEach(lanes.add);
    return LaneGraph._(
      lanes,
      lanes.lanes.length,
      lanes.peers.length,
      List.unmodifiable(lanes.first),
      List.unmodifiable(lanes.last),
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
      peers = <String>[],
      lanes = <int>[],
      merges = <List<int>>[],
      first = List<int>.filled(LaneGraph.maxLanes, -1),
      last = List<int>.filled(LaneGraph.maxLanes, -1);

  factory _Lanes.copyOf(LaneGraph graph) {
    final copy = _Lanes();
    final source = graph._lanes;
    if (source == null) return copy;
    copy.peers.addAll(source.peers.take(graph._peerCount));
    for (final peer in copy.peers) {
      copy.laneOf[peer] = source.laneOf[peer]!;
    }
    copy.lanes.addAll(source.lanes.take(graph._length));
    copy.merges.addAll(source.merges.take(graph._length));
    copy.first.setAll(0, graph._first);
    copy.last.setAll(0, graph._last);
    return copy;
  }

  final Map<String, int> laneOf;

  final List<String> peers;

  final List<int> lanes;

  final List<List<int>> merges;

  final List<int> first;

  final List<int> last;

  void add(GraphNode node) {
    final row = lanes.length;
    final lane = laneOf[node.author] ??= _newLane(node.author);
    lanes.add(lane);
    if (first[lane] < 0) first[lane] = row;
    last[lane] = row;
    final from = <int>{
      for (final author in node.depAuthors)
        if (laneOf[author] case final l? when l != lane) l,
    };
    merges.add(
      from.isEmpty ? const [] : List.unmodifiable(from.toList()..sort()),
    );
  }

  int _newLane(String author) {
    peers.add(author);
    return peers.length < LaneGraph.maxLanes
        ? peers.length - 1
        : LaneGraph.maxLanes - 1;
  }
}
