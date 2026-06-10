import 'dart:typed_data';

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';

import '../common/custom_emitter.dart';

VersionVector _makeVersionVector(int peerCount) {
  final map = <PeerId, HybridLogicalClock>{};
  for (var i = 0; i < peerCount; i++) {
    map[PeerId.generate()] = HybridLogicalClock(l: 1700000000000 + i, c: 0);
  }
  return VersionVector(map);
}

/// Benchmarks VersionVector.toBytes() on a 10-entry vector.
///
/// Each call allocates a Uint8List and serialises all entries.
class VersionVectorToBytesBenchmark extends BenchmarkBase {
  VersionVectorToBytesBenchmark()
      : super(
          'VersionVector toBytes 10 peers x1000',
          emitter: const CustomEmitter(),
        );

  late final VersionVector vv;

  @override
  void setup() {
    vv = _makeVersionVector(10);
  }

  @override
  void run() {
    for (var i = 0; i < 1000; i++) {
      vv.toBytes();
    }
  }
}

/// Benchmarks VersionVector.fromBytes() on a 10-entry vector.
class VersionVectorFromBytesBenchmark extends BenchmarkBase {
  VersionVectorFromBytesBenchmark()
      : super(
          'VersionVector fromBytes 10 peers x1000',
          emitter: const CustomEmitter(),
        );

  late final Uint8List bytes;

  @override
  void setup() {
    bytes = _makeVersionVector(10).toBytes();
  }

  @override
  void run() {
    for (var i = 0; i < 1000; i++) {
      VersionVector.fromBytes(bytes);
    }
  }
}

/// Benchmarks VersionVector.intersection() on two 10-entry vectors.
///
/// The public `entries` getter copies the map before iterating,
/// which means each intersection call allocates 2× 10 HLC copies.
class VersionVectorIntersectionBenchmark extends BenchmarkBase {
  VersionVectorIntersectionBenchmark()
      : super(
          'VersionVector intersection 10 peers x1000',
          emitter: const CustomEmitter(),
        );

  late final List<VersionVector> vectors;

  @override
  void setup() {
    vectors = List.generate(2, (_) => _makeVersionVector(10));
  }

  @override
  void run() {
    for (var i = 0; i < 1000; i++) {
      VersionVector.intersection(vectors);
    }
  }
}

void main() {
  VersionVectorToBytesBenchmark().report();
  VersionVectorFromBytesBenchmark().report();
  VersionVectorIntersectionBenchmark().report();
}
