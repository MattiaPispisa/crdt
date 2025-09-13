import 'package:benchmark_harness/benchmark_harness.dart';

/// A custom benchmark emitter that prints the results in
/// microseconds, milliseconds, and seconds.
class CustomEmitter implements ScoreEmitter {
  /// Creates a new custom emitter
  const CustomEmitter();

  @override
  void emit(String testName, double value) {
    final microseconds = value;
    final milliseconds = value / 1000;
    final seconds = value / 1000000;

    // ignore: avoid_print benchmark_harness results
    print('$testName(RunTime): '
        '$microseconds us | '
        '${milliseconds.toStringAsFixed(4)} ms | '
        '${seconds.toStringAsFixed(6)} s');
  }
}
