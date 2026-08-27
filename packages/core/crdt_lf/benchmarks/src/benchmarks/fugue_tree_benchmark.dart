import 'dart:math';

import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/algorithm/fugue/tree.dart';
import 'package:crdt_lf/src/algorithm/fugue/value_node.dart';

const _kElements = 50000;

final _peer = PeerId.generate();

FugueValueNode<String> _node(int counter) => FugueValueNode<String>(
      id: FugueElementID(_peer, counter),
      value: 'x',
    );

/// Builds a tree of [count] elements by appending at the end, the shape a
/// document typed from start to finish produces.
FugueTree<String> _appendedTree(int count) {
  final tree = FugueTree<String>.empty();
  for (var i = 0; i < count; i++) {
    tree.iterableInsert(i, [_node(i)]);
  }
  return tree;
}

/// Appending at the end of the sequence: the sequential-typing path.
class FugueTreeAppendBenchmark extends TimedBenchmarkBase {
  FugueTreeAppendBenchmark() : super('FugueTree append $_kElements elements');

  @override
  void run() {
    _appendedTree(_kElements);
  }
}

/// Inserting at position 0 every time: the prepend path, which builds a left
/// spine instead of a right one.
class FugueTreePrependBenchmark extends TimedBenchmarkBase {
  FugueTreePrependBenchmark() : super('FugueTree prepend $_kElements elements');

  @override
  void run() {
    final tree = FugueTree<String>.empty();
    for (var i = 0; i < _kElements; i++) {
      tree.iterableInsert(0, [_node(i)]);
    }
  }
}

/// Inserting at a random position: the editing-inside-a-document path.
class FugueTreeRandomInsertBenchmark extends TimedBenchmarkBase {
  FugueTreeRandomInsertBenchmark()
      : super('FugueTree random insert $_kElements elements');

  late List<int> _positions;

  @override
  void setup() {
    // Fixed seed so every run inserts at the same positions.
    final random = Random(42);
    _positions = [
      for (var i = 0; i < _kElements; i++) i == 0 ? 0 : random.nextInt(i),
    ];
  }

  @override
  void run() {
    final tree = FugueTree<String>.empty();
    for (var i = 0; i < _kElements; i++) {
      tree.iterableInsert(_positions[i], [_node(i)]);
    }
  }
}

/// Reading the whole sequence back, with every element live.
class FugueTreeValuesBenchmark extends TimedBenchmarkBase {
  FugueTreeValuesBenchmark()
      : super('FugueTree values() over $_kElements live elements');

  late FugueTree<String> _tree;

  @override
  void setup() {
    _tree = _appendedTree(_kElements);
  }

  @override
  void run() {
    _tree.values();
  }
}

/// Reading the whole sequence back when 90% of the elements are tombstones,
/// the shape a long-lived document converges to.
class FugueTreeValuesWithTombstonesBenchmark extends TimedBenchmarkBase {
  FugueTreeValuesWithTombstonesBenchmark()
      : super('FugueTree values() over $_kElements elements, 90% tombstones');

  late FugueTree<String> _tree;

  @override
  void setup() {
    _tree = _appendedTree(_kElements);
    for (var i = 0; i < _kElements; i++) {
      if (i % 10 != 0) {
        _tree.delete(FugueElementID(_peer, i));
      }
    }
  }

  @override
  void run() {
    _tree.values();
  }
}

void main() {
  FugueTreeAppendBenchmark().report();
  FugueTreePrependBenchmark().report();
  FugueTreeRandomInsertBenchmark().report();
  FugueTreeValuesBenchmark().report();
  FugueTreeValuesWithTombstonesBenchmark().report();
}
