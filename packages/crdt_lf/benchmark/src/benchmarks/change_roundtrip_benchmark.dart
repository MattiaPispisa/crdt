import 'dart:typed_data';

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:crdt_lf/crdt_lf.dart';

import '../common/custom_emitter.dart';

/// Benchmarks Change.toBytes() for 1000 changes.
///
/// Measures the per-change serialisation cost: envelope encoding +
/// schema version byte + varint deps count + payload length varint.
class ChangeToBytesBenchmark extends BenchmarkBase {
  ChangeToBytesBenchmark()
      : super('Change toBytes x1000', emitter: const CustomEmitter());

  late final List<Change> changes;

  @override
  void setup() {
    final doc = CRDTDocument(peerId: PeerId.generate());
    final list = CRDTListHandler<String>(doc, 'list');
    for (var i = 0; i < 1000; i++) {
      list.insert(i, 'item $i');
    }
    changes = doc.exportChanges();
  }

  @override
  void run() {
    for (final change in changes) {
      change.toBytes();
    }
  }
}

/// Benchmarks Change.fromBytes() for 1000 changes.
///
/// Measures the per-change deserialisation cost.  Note that decoded fields
/// (id, author, deps) are lazy-cached on the resulting Change object, so this
/// only measures the structural parsing, not field access.
class ChangeFromBytesBenchmark extends BenchmarkBase {
  ChangeFromBytesBenchmark()
      : super('Change fromBytes x1000', emitter: const CustomEmitter());

  late final List<Uint8List> encoded;

  @override
  void setup() {
    final doc = CRDTDocument(peerId: PeerId.generate());
    final list = CRDTListHandler<String>(doc, 'list');
    for (var i = 0; i < 1000; i++) {
      list.insert(i, 'item $i');
    }
    encoded = doc.exportChanges().map((c) => c.toBytes()).toList();
  }

  @override
  void run() {
    for (final bytes in encoded) {
      Change.fromBytes(bytes);
    }
  }
}

/// Benchmarks the full Change roundtrip: toBytes() + fromBytes().
class ChangeRoundtripBenchmark extends BenchmarkBase {
  ChangeRoundtripBenchmark()
      : super('Change roundtrip x1000', emitter: const CustomEmitter());

  late final List<Change> changes;

  @override
  void setup() {
    final doc = CRDTDocument(peerId: PeerId.generate());
    final list = CRDTListHandler<String>(doc, 'list');
    for (var i = 0; i < 1000; i++) {
      list.insert(i, 'item $i');
    }
    changes = doc.exportChanges();
  }

  @override
  void run() {
    for (final change in changes) {
      Change.fromBytes(change.toBytes());
    }
  }
}

void main() {
  ChangeToBytesBenchmark().report();
  ChangeFromBytesBenchmark().report();
  ChangeRoundtripBenchmark().report();
}
