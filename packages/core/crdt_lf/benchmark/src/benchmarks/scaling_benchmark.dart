import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:crdt_lf/crdt_lf.dart';

import '../common/custom_emitter.dart';

/// Imports a linear chain of [count] changes into a fresh document.
///
/// Demonstrates the cost of the topological sort and apply path as the
/// number of changes grows.
class ImportChainBenchmark extends BenchmarkBase {
  ImportChainBenchmark(this.count)
      : super(
          'Import $count chained changes',
          emitter: const CustomEmitter(),
        );

  final int count;
  late final List<Change> changes;

  @override
  void setup() {
    final doc = CRDTDocument(peerId: PeerId.generate());
    final list = CRDTListHandler<String>(doc, 'list');
    for (var i = 0; i < count; i++) {
      list.insert(i, 'item $i');
    }
    changes = doc.exportChanges();
  }

  @override
  void run() {
    CRDTDocument(peerId: PeerId.generate()).importChanges(changes);
  }
}

/// Exports the changes that a nearly caught-up peer is missing from a
/// document holding [count] changes spread across [peers] peers.
///
/// This is the sync-server hot path: one call per client sync request.
class ExportNewerThanBenchmark extends BenchmarkBase {
  ExportNewerThanBenchmark({required this.count, required this.peers})
      : super(
          'exportChangesNewerThan on $count changes / $peers peers '
          '(99% caught-up)',
          emitter: const CustomEmitter(),
        );

  final int count;
  final int peers;
  late final CRDTDocument doc;
  late final VersionVector nearlyCaughtUp;

  @override
  void setup() {
    doc = CRDTDocument(peerId: PeerId.generate());

    final docs = List.generate(
      peers,
      (_) => CRDTDocument(peerId: PeerId.generate()),
    );
    final lists = [
      for (final d in docs) CRDTListHandler<String>(d, 'list'),
    ];
    final perPeer = count ~/ peers;
    for (var p = 0; p < peers; p++) {
      for (var i = 0; i < perPeer; i++) {
        lists[p].insert(i, 'item $i');
      }
    }
    for (final d in docs) {
      doc.importChanges(d.exportChanges());
    }

    // Capture the version vector when 99% of changes are known.
    final all = doc.exportChanges().sorted();
    final cutoff = all.length * 99 ~/ 100;
    final partial = CRDTDocument(peerId: PeerId.generate())
      ..importChanges(all.sublist(0, cutoff));
    nearlyCaughtUp = partial.getVersionVector();
  }

  @override
  void run() {
    doc.exportChangesNewerThan(nearlyCaughtUp);
  }
}

/// Takes a pruning snapshot of a document holding [count] changes.
///
/// Exercises `ChangeStore.prune` and `DAG.prune`.
class SnapshotPruneBenchmark extends BenchmarkBase {
  SnapshotPruneBenchmark(this.count)
      : super(
          'takeSnapshot(pruneHistory) with $count changes',
          emitter: const CustomEmitter(),
        );

  final int count;
  late final List<Change> changes;

  @override
  void setup() {
    final doc = CRDTDocument(peerId: PeerId.generate());
    final list = CRDTListHandler<String>(doc, 'list');
    for (var i = 0; i < count; i++) {
      list.insert(i, 'item $i');
    }
    changes = doc.exportChanges();
  }

  @override
  void run() {
    final doc = CRDTDocument(peerId: PeerId.generate());
    CRDTListHandler<String>(doc, 'list');
    doc
      ..importChanges(changes)
      ..takeSnapshot();
  }
}

/// Prunes a document whose frontier holds [peers] concurrent heads.
///
/// Exercises `Frontiers.merge` under high concurrency, where the current
/// implementation is quadratic (and collapses concurrent heads).
class ConcurrentFrontierPruneBenchmark extends BenchmarkBase {
  ConcurrentFrontierPruneBenchmark(this.peers)
      : super(
          'takeSnapshot(pruneHistory) with $peers concurrent heads',
          emitter: const CustomEmitter(),
        );

  final int peers;
  late final List<List<Change>> peerChanges;

  @override
  void setup() {
    peerChanges = [];
    for (var p = 0; p < peers; p++) {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final list = CRDTListHandler<String>(doc, 'list');
      for (var i = 0; i < 10; i++) {
        list.insert(i, 'p$p item $i');
      }
      peerChanges.add(doc.exportChanges());
    }
  }

  @override
  void run() {
    final doc = CRDTDocument(peerId: PeerId.generate());
    CRDTListHandler<String>(doc, 'list');
    for (final changes in peerChanges) {
      doc.importChanges(changes);
    }
    doc.takeSnapshot();
  }
}

void main() {
  ImportChainBenchmark(1000).report();
  ImportChainBenchmark(10000).report();
  ExportNewerThanBenchmark(count: 50000, peers: 10).report();
  SnapshotPruneBenchmark(10000).report();
  ConcurrentFrontierPruneBenchmark(100).report();
}
