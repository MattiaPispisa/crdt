import 'dart:convert';

/// Prefix marking a machine-readable memory result line in a benchmark's
/// stdout.
///
/// Distinct from `benchmarkResultMarker` (the timed marker) even though the
/// two never share a stdout stream: each `*_benchmark.dart` file runs as its
/// own subprocess under either the timed or the memory runner, never both.
const memoryResultMarker = '@@MEMORY_BENCHMARK_RESULT@@';

/// Emits the memory footprint of a benchmark.
abstract class MemoryEmitter {
  /// Emits a single measurement of [bytes] for [testName].
  void emit(String testName, int bytes);
}

/// Prints one [memoryResultMarker]-tagged JSON line per result:
/// `{"name": ..., "bytes": ...}`, mirroring `CustomEmitter`.
class PrintMemoryEmitter implements MemoryEmitter {
  /// Creates a new print emitter.
  const PrintMemoryEmitter();

  @override
  void emit(String testName, int bytes) {
    // ignore: avoid_print memory benchmark results
    print(
      '$memoryResultMarker'
      '${jsonEncode({'name': testName, 'bytes': bytes})}',
    );
  }
}
