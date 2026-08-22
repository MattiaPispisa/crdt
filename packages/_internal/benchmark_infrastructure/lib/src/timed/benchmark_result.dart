import 'dart:convert';

import 'package:benchmark_infrastructure/src/timed/custom_emitter.dart';

/// A single parsed benchmark result line, as printed by [CustomEmitter].
class BenchmarkResult {
  /// Creates a result already split into name and timing components.
  const BenchmarkResult({
    required this.name,
    required this.sourceFile,
    required this.microseconds,
    required this.milliseconds,
    required this.seconds,
  });

  /// Parses one line of [CustomEmitter] output.
  ///
  /// Returns `null` if [line] doesn't start with [benchmarkResultMarker] —
  /// every other line (progress output, a stray print in a benchmark) is
  /// left for the caller to report instead of guessing at its shape. A line
  /// that does start with the marker is decoded as JSON without a fallback:
  /// this package controls both sides of that line, so a decode failure
  /// means the emitter and parser drifted and should fail loudly.
  static BenchmarkResult? tryParse(
    String line, {
    required String sourceFile,
  }) {
    if (!line.startsWith(benchmarkResultMarker)) {
      return null;
    }
    final json = jsonDecode(line.substring(benchmarkResultMarker.length))
        as Map<String, dynamic>;
    final microseconds = (json['microseconds'] as num).toDouble();
    return BenchmarkResult(
      name: json['name'] as String,
      sourceFile: sourceFile,
      microseconds: microseconds,
      milliseconds: microseconds / 1000,
      seconds: microseconds / 1000000,
    );
  }

  /// The benchmark's name, as passed to `TimedBenchmarkBase`.
  final String name;

  /// The file that produced this result (e.g. `dag_benchmark.dart`).
  final String sourceFile;

  /// The measured cost of one `run()`, in microseconds.
  final double microseconds;

  /// The measured cost of one `run()`, in milliseconds.
  final double milliseconds;

  /// The measured cost of one `run()`, in seconds.
  final double seconds;
}
