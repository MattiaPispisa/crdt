import 'dart:typed_data';

import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';
import 'package:hlc_dart/hlc_dart.dart';

/// Benchmarks HybridLogicalClock.toUint8List() — encodes l/c to 8 bytes.
class HLCToBytesBenchmark extends TimedBenchmarkBase {
  HLCToBytesBenchmark() : super('HLC toUint8List x100k');

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
class HLCFromBytesBenchmark extends TimedBenchmarkBase {
  HLCFromBytesBenchmark() : super('HLC fromUint8List x100k');

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
class HLCCompareBenchmark extends TimedBenchmarkBase {
  HLCCompareBenchmark() : super('HLC compareTo x100k');

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

/// Benchmarks HybridLogicalClock.localEvent() with a physical time that
/// stays behind the clock, so every call increments the counter.
class HLCLocalEventBenchmark extends TimedBenchmarkBase {
  HLCLocalEventBenchmark() : super('HLC localEvent x100k');

  static const int _base = 1700000000000;

  @override
  void run() {
    final clock = HybridLogicalClock(l: _base, c: 0);
    for (var i = 0; i < 100000; i++) {
      clock.localEvent(_base);
    }
  }
}

/// Benchmarks HybridLogicalClock.receiveEvent() with received clocks just
/// before, equal to and just after the local one.
class HLCReceiveEventBenchmark extends TimedBenchmarkBase {
  HLCReceiveEventBenchmark() : super('HLC receiveEvent x100k');

  static const int _base = 1700000000000;

  late final List<HybridLogicalClock> received;

  @override
  void setup() {
    received = List.generate(
      100000,
      (i) => HybridLogicalClock(l: _base + i ~/ 2 + (i % 3) - 1, c: i % 8),
    );
  }

  @override
  void run() {
    final clock = HybridLogicalClock(l: _base, c: 0);
    for (var i = 0; i < received.length; i++) {
      clock.receiveEvent(_base + i ~/ 4, received[i]);
    }
  }
}

void main() {
  HLCToBytesBenchmark().report();
  HLCFromBytesBenchmark().report();
  HLCCompareBenchmark().report();
  HLCLocalEventBenchmark().report();
  HLCReceiveEventBenchmark().report();
}
