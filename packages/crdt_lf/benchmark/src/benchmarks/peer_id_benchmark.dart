import 'dart:typed_data';

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:crdt_lf/crdt_lf.dart';

import '../common/custom_emitter.dart';

/// Benchmarks PeerId.generate() — UUID v4 random generation.
class PeerIdGenerateBenchmark extends BenchmarkBase {
  PeerIdGenerateBenchmark()
      : super('PeerId generate x100', emitter: const CustomEmitter());

  @override
  void run() {
    for (var i = 0; i < 100; i++) {
      PeerId.generate();
    }
  }
}

/// Benchmarks PeerId.toUint8List() — hex string → bytes.
class PeerIdToBytesBenchmark extends BenchmarkBase {
  PeerIdToBytesBenchmark()
      : super('PeerId toUint8List x1000', emitter: const CustomEmitter());

  late final List<PeerId> peers;

  @override
  void setup() {
    peers = List.generate(1000, (_) => PeerId.generate());
  }

  @override
  void run() {
    for (final peer in peers) {
      peer.toUint8List();
    }
  }
}

/// Benchmarks PeerId.fromUint8List() — bytes → UUID string + regex validation.
///
/// This is called on every Change decode (via OperationId.fromUint8List).
/// The bottleneck is the regex validation inside PeerId.parse().
class PeerIdFromBytesBenchmark extends BenchmarkBase {
  PeerIdFromBytesBenchmark()
      : super('PeerId fromUint8List x1000', emitter: const CustomEmitter());

  late final List<Uint8List> bytesList;

  @override
  void setup() {
    bytesList = List.generate(
      1000,
      (_) => PeerId.generate().toUint8List(),
    );
  }

  @override
  void run() {
    for (final bytes in bytesList) {
      PeerId.fromUint8List(bytes);
    }
  }
}

void main() {
  PeerIdGenerateBenchmark().report();
  PeerIdToBytesBenchmark().report();
  PeerIdFromBytesBenchmark().report();
}
