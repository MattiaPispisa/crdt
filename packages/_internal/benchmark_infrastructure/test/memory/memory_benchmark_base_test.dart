@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';
import 'package:test/test.dart';

const _allocatedBytes = 8 * 1024 * 1024;

class _CapturingEmitter implements MemoryEmitter {
  final results = <String, int>{};

  @override
  void emit(String testName, int bytes) => results[testName] = bytes;
}

/// Allocates a known number of bytes and hands them back to be measured.
class _AllocateBenchmark extends MemoryBenchmarkBase {
  _AllocateBenchmark(MemoryEmitter emitter)
      : super('allocate', emitter: emitter);

  @override
  Object? run() => Uint8List(_allocatedBytes);
}

/// Drops what it allocates instead of returning it, the mistake the
/// return value of `run()` exists to prevent.
class _DiscardingBenchmark extends MemoryBenchmarkBase {
  _DiscardingBenchmark(MemoryEmitter emitter)
      : super('discard', emitter: emitter);

  @override
  Object? run() {
    Uint8List(_allocatedBytes);
    return null;
  }
}

class _ThrowingBenchmark extends MemoryBenchmarkBase {
  _ThrowingBenchmark() : super('throwing');

  bool tornDown = false;

  @override
  Object? run() => throw StateError('boom');

  @override
  void teardown() => tornDown = true;
}

void main() {
  group('MemoryBenchmarkBase.report', () {
    test('measures the bytes retained by what run() returns', () async {
      final emitter = _CapturingEmitter();

      await _AllocateBenchmark(emitter).report();

      // A loose band: leftover garbage shifts the delta either way, so it
      // is never exact. In practice it lands within a few thousand bytes.
      expect(
        emitter.results['allocate'],
        closeTo(_allocatedBytes, _allocatedBytes ~/ 4),
      );
    });

    test('measures far less when run() drops what it allocates', () async {
      final emitter = _CapturingEmitter();

      await _DiscardingBenchmark(emitter).report();

      expect(emitter.results['discard'], lessThan(_allocatedBytes ~/ 2));
    });

    test('runs teardown() when run() throws', () async {
      final benchmark = _ThrowingBenchmark();

      await expectLater(benchmark.report(), throwsStateError);

      expect(benchmark.tornDown, isTrue);
    });
  });
}
