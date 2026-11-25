// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/application/changes/row_graph.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  GraphNode node(String author, [List<String> deps = const []]) => (
    author: author,
    depAuthors: deps,
  );

  // lane, active lanes, merged lanes.
  List<String> rowsOf(LaneGraph graph) => [
    for (final row in graph.rows) '${row.lane} ${row.active} ${row.mergesFrom}',
  ];

  test('one peer has one lane', () {
    final graph = LaneGraph([
      node('a'),
      node('a', ['a']),
      node('a', ['a']),
    ]);
    expect(graph.peers, ['a']);
    expect(graph.laneCount, 1);
    expect(rowsOf(graph), ['0 [0] []', '0 [0] []', '0 [0] []']);
  });

  test('two peers that never merge', () {
    final graph = LaneGraph([
      node('a'),
      node('b'),
      node('a', ['a']),
      node('b', ['b']),
      node('b', ['b']),
    ]);
    expect(graph.peers, ['a', 'b']);
    expect(rowsOf(graph), [
      '0 [0] []',
      '1 [0, 1] []',
      '0 [0, 1] []',
      '1 [1] []',
      '1 [1] []',
    ]);
  });

  test('two peers with a merge', () {
    final graph = LaneGraph([
      node('a'),
      node('b'),
      node('a', ['a', 'b']),
      // A dependency on an author with no earlier change (pruned) draws
      // no merge.
      node('a', ['a', 'gone']),
    ]);
    expect(rowsOf(graph), ['0 [0] []', '1 [0, 1] []', '0 [0] [1]', '0 [0] []']);
  });

  test('seven peers share the last lane from the sixth one', () {
    final authors = ['p0', 'p1', 'p2', 'p3', 'p4', 'p5', 'p6'];
    final graph = LaneGraph([
      for (final author in authors) node(author),
      node('p6', ['p5', 'p0']),
    ]);
    expect(graph.peers, authors);
    expect(graph.laneCount, LaneGraph.maxLanes);
    expect(graph.sharedLastLane, isTrue);
    expect([for (final row in graph.rows) row.lane], [0, 1, 2, 3, 4, 5, 5, 5]);
    // p5 and p6 share lane 5: only the merge from p0 crosses lanes.
    expect(graph.rows.last.mergesFrom, [0]);
    expect(graph.rows.last.active, [5]);
    expect(graph.rows[3].active, [3]);
    expect(graph.rows[6].active, [5]);
  });

  test('a graph with its last rows replaced is the graph of its nodes', () {
    final kept = [
      node('a'),
      node('b'),
      node('a', ['a', 'b']),
    ];
    final graph = LaneGraph([
      ...kept,
      node('c', ['a']),
      node('b', ['b', 'c']),
    ]);
    // `c` leaves with the rows it came in, and `d` takes its lane.
    final added = [
      node('d', ['a']),
      node('b', ['b', 'd']),
      node('a', ['a']),
    ];

    final replaced = graph.replaceFrom(kept.length, added);
    final fresh = LaneGraph([...kept, ...added]);

    expect(rowsOf(replaced), rowsOf(fresh));
    expect(replaced.peers, fresh.peers);
    expect(replaced.laneCount, fresh.laneCount);
  });

  test('an extended graph is the graph of all its nodes', () {
    final nodes = [
      node('a'),
      node('b'),
      node('a', ['a', 'b']),
      node('c', ['a']),
      node('b', ['b', 'c']),
    ];
    final all = LaneGraph(nodes);
    final base = LaneGraph(nodes.sublist(0, 2));
    final extended = base.extend(nodes.sublist(2));
    // A second extension of the same base must not see the first one.
    final again = base.extend(nodes.sublist(2, 4));

    expect(rowsOf(extended), rowsOf(all));
    expect(extended.peers, all.peers);
    expect(rowsOf(again), rowsOf(LaneGraph(nodes.sublist(0, 4))));
    expect(rowsOf(base), rowsOf(LaneGraph(nodes.sublist(0, 2))));
    expect(base.peers, ['a', 'b']);
  });
}
