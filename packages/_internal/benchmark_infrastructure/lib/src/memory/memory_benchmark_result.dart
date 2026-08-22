import 'dart:convert';

import 'package:benchmark_infrastructure/src/memory/memory_emitter.dart';

/// A single parsed memory benchmark result line, as printed by
/// [PrintMemoryEmitter].
class MemoryBenchmarkResult {
  /// Creates a result already split into name and size components.
  const MemoryBenchmarkResult({
    required this.name,
    required this.sourceFile,
    required this.bytes,
    required this.kilobytes,
    required this.megabytes,
  });

  /// Parses one line of [PrintMemoryEmitter] output.
  ///
  /// Returns `null` if [line] doesn't start with [memoryResultMarker] —
  /// every other line (progress output, the VM service's own startup
  /// banner) is left for the caller to report instead of guessing at its
  /// shape. A line that does start with the marker is decoded as JSON
  /// without a fallback: this package controls both sides of that line, so a
  /// decode failure means the emitter and parser drifted and should fail
  /// loudly.
  static MemoryBenchmarkResult? tryParse(
    String line, {
    required String sourceFile,
  }) {
    if (!line.startsWith(memoryResultMarker)) {
      return null;
    }
    final json = jsonDecode(line.substring(memoryResultMarker.length))
        as Map<String, dynamic>;
    final bytes = (json['bytes'] as num).toInt();
    return MemoryBenchmarkResult(
      name: json['name'] as String,
      sourceFile: sourceFile,
      bytes: bytes,
      kilobytes: bytes / 1024,
      megabytes: bytes / (1024 * 1024),
    );
  }

  /// The benchmark's name, as passed to `MemoryBenchmarkBase`.
  final String name;

  /// The file that produced this result (e.g. `fugue_tree_benchmark.dart`).
  final String sourceFile;

  /// The measured heap delta caused by `run()`, in bytes.
  final int bytes;

  /// The measured heap delta caused by `run()`, in kilobytes.
  final double kilobytes;

  /// The measured heap delta caused by `run()`, in megabytes.
  final double megabytes;
}
