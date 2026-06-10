import 'dart:typed_data';

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:hlc_dart/hlc_dart.dart';

import '../common/custom_emitter.dart';

/// Benchmarks HybridLogicalClock.toUint8List() — encodes l/c to 8 bytes.
///
/// The current implementation uses float division: (_l / 4294967296).floor().
/// The fix uses integer truncating division: _l ~/ 0x100000000.
class HLCToBytesBenchmark extends BenchmarkBase {
  HLCToBytesBenchmark()
      : super('HLC toUint8List x100k', emitter: const CustomEmitter());

  late final List<HybridLogicalClock> clocks;

  @override
  void setup() {
    clocks = List.generate(
      100000,
      (i) => HybridLogicalClock(l: 1700000000000 + i, c: i % 65536),
    );
  }

  @override
  void run() {
    for (final clock in clocks) {
      clock.toUint8List();
    }
  }
}

/// Benchmarks HybridLogicalClock.fromUint8List() — decodes 8 bytes to l/c.
class HLCFromBytesBenchmark extends BenchmarkBase {
  HLCFromBytesBenchmark()
      : super('HLC fromUint8List x100k', emitter: const CustomEmitter());

  late final List<Uint8List> bytesList;

  @override
  void setup() {
    bytesList = List.generate(
      100000,
      (i) =>
          HybridLogicalClock(l: 1700000000000 + i, c: i % 65536).toUint8List(),
    );
  }

  @override
  void run() {
    for (final bytes in bytesList) {
      HybridLogicalClock.fromUint8List(bytes);
    }
  }
}

/// Benchmarks HybridLogicalClock.compareTo() — hot path in change sorting.
class HLCCompareBenchmark extends BenchmarkBase {
  HLCCompareBenchmark()
      : super('HLC compareTo x100k', emitter: const CustomEmitter());

  late final List<HybridLogicalClock> clocks;

  @override
  void setup() {
    clocks = List.generate(
      100000,
      (i) => HybridLogicalClock(l: 1700000000000 + i, c: i % 65536),
    );
  }

  @override
  void run() {
    for (var i = 0; i < clocks.length - 1; i++) {
      clocks[i].compareTo(clocks[i + 1]);
    }
  }
}

void main() {
  HLCToBytesBenchmark().report();
  HLCFromBytesBenchmark().report();
  HLCCompareBenchmark().report();
}
