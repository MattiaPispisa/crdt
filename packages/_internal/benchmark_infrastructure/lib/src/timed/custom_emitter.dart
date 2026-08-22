import 'dart:convert';

import 'package:benchmark_harness/benchmark_harness.dart';

/// Prefix marking a machine-readable result line in a benchmark's stdout.
///
/// `BenchmarkResult.tryParse` looks for this exact prefix at the start of a
/// line and decodes everything after it as JSON. A result line is never
/// confused with other output, and adding or renaming a field only touches
/// the JSON payload — not a parser that has to be kept in sync with a
/// human-readable sentence.
const benchmarkResultMarker = '@@BENCHMARK_RESULT@@';

/// A custom benchmark emitter that prints one [benchmarkResultMarker]-tagged
/// JSON line per result: `{"name": ..., "microseconds": ...}`.
///
/// Everything it reports is the cost of **one** `run()`, so two lines of
/// `results.md` can be compared and a number can be quoted in a CHANGELOG as
/// it stands.
class CustomEmitter implements ScoreEmitter {
  /// Creates an emitter for a benchmark whose measured value covers
  /// [runsPerMeasure] calls of `run()`.
  ///
  /// The default is `BenchmarkBase.exercise`, which calls `run()` ten times —
  /// so a benchmark that keeps the harness loop reports ten calls per measure
  /// and this is what divides them back out. A benchmark that overrides
  /// `measure()` to time a fixed number of cycles already reports one call and
  /// passes `1`.
  const CustomEmitter({this.runsPerMeasure = 10});

  /// How many `run()` calls the measured value covers.
  final int runsPerMeasure;

  @override
  void emit(String testName, double value) {
    final microseconds = value / runsPerMeasure;

    // ignore: avoid_print benchmark_harness results
    print(
      '$benchmarkResultMarker'
      '${jsonEncode({'name': testName, 'microseconds': microseconds})}',
    );
  }
}
