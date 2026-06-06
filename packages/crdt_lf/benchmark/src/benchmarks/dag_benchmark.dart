import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';

import '../common/custom_emitter.dart';

/// Benchmarks DAG.addNode with a chain of 1000 sequential nodes
/// (each node depends on the previous one).
class DAGAddNodeChainBenchmark extends BenchmarkBase {
  DAGAddNodeChainBenchmark()
      : super('DAG addNode chain of 1000', emitter: const CustomEmitter());

  late final List<OperationId> ids;

  @override
  void setup() {
    final peer = PeerId.generate();
    ids = List.generate(
      1000,
      (i) => OperationId(peer, HybridLogicalClock(l: i + 1, c: 0)),
    );
  }

  @override
  void run() {
    final dag = DAG.empty()..addNode(ids[0], {});
    for (var i = 1; i < ids.length; i++) {
      dag.addNode(ids[i], {ids[i - 1]});
    }
  }
}

/// Benchmarks DAG.getAncestors on a chain of 200 nodes.
///
/// Without fix: O(n²) because BFS uses List.removeAt(0).
/// With fix: O(n) using DFS stack with removeLast().
class DAGGetAncestorsBenchmark extends BenchmarkBase {
  DAGGetAncestorsBenchmark()
      : super(
          'DAG getAncestors chain of 200',
          emitter: const CustomEmitter(),
        );

  late final DAG dag;
  late final OperationId lastId;

  @override
  void setup() {
    dag = DAG.empty();
    final peer = PeerId.generate();
    final ids = List.generate(
      200,
      (i) => OperationId(peer, HybridLogicalClock(l: i + 1, c: 0)),
    );
    dag.addNode(ids[0], {});
    for (var i = 1; i < ids.length; i++) {
      dag.addNode(ids[i], {ids[i - 1]});
    }
    lastId = ids.last;
  }

  @override
  void run() {
    dag.getAncestors(lastId);
  }
}

void main() {
  DAGAddNodeChainBenchmark().report();
  DAGGetAncestorsBenchmark().report();
}
