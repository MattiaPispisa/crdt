// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

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
  factory LaneGraph(List<GraphNode> nodes) {
    final laneOf = <String, int>{};
    final peers = <String>[];
    final lanes = List<int>.filled(nodes.length, 0);
    final merges = List<List<int>>.filled(nodes.length, const []);
    final first = List<int>.filled(maxLanes, -1);
    final last = List<int>.filled(maxLanes, -1);
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final lane = laneOf[node.author] ??= _newLane(peers, node.author);
      lanes[i] = lane;
      if (first[lane] < 0) first[lane] = i;
      last[lane] = i;
      final from = <int>{
        for (final author in node.depAuthors)
          if (laneOf[author] case final l? when l != lane) l,
      };
      if (from.isNotEmpty) merges[i] = from.toList()..sort();
    }
    return LaneGraph._(peers, [
      for (var i = 0; i < nodes.length; i++)
        RowGraph(
          lane: lanes[i],
          activeMask: _activeAt(i, first, last),
          mergesFrom: merges[i],
        ),
    ]);
  }

  const LaneGraph._(this.peers, this.rows);

  /// The graph of no change.
  static const LaneGraph empty = LaneGraph._([], []);

  /// The most lanes a graph draws.
  static const int maxLanes = 6;

  /// The authors in the order they first appear; author `n` is on lane `n`,
  /// up to the last lane.
  final List<String> peers;

  /// One graph per row, in replay order.
  final List<RowGraph> rows;

  /// The number of lanes drawn.
  int get laneCount => peers.length < maxLanes ? peers.length : maxLanes;

  /// Whether the last lane holds more than one author.
  bool get sharedLastLane => peers.length > maxLanes;

  static int _newLane(List<String> peers, String author) {
    peers.add(author);
    return peers.length < maxLanes ? peers.length - 1 : maxLanes - 1;
  }

  static int _activeAt(int row, List<int> first, List<int> last) {
    var mask = 0;
    for (var lane = 0; lane < maxLanes; lane++) {
      if (first[lane] >= 0 && first[lane] <= row && row <= last[lane]) {
        mask |= 1 << lane;
      }
    }
    return mask;
  }
}
