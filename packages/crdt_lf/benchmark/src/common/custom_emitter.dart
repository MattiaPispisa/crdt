import 'package:benchmark_harness/benchmark_harness.dart';

/// A custom benchmark emitter that prints the results in
/// microseconds, milliseconds, and seconds.
///
/// Everything it prints is the cost of **one** `run()`, so two lines of
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
    final milliseconds = microseconds / 1000;
    final seconds = microseconds / 1000000;

    // ignore: avoid_print benchmark_harness results
    print('$testName(RunTime): '
        '$microseconds us | '
        '${milliseconds.toStringAsFixed(4)} ms | '
        '${seconds.toStringAsFixed(6)} s');
  }
}
