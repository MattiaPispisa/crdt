import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';

/// A fixed-cycle benchmark whose cycles each need untimed work first, such as
/// a remote peer writing the change the cycle then applies.
///
/// It warms up by time, then runs 5 batches of 200 timed cycles, calling
/// [setup] before each batch, and reports the fastest batch.
abstract class PreparedCycleBenchmark extends TimedBenchmarkBase {
  /// Creates the benchmark reported under `name`.
  PreparedCycleBenchmark(super.name) : super(runsPerMeasure: 1);

  static const _warmup = Duration(milliseconds: 400);
  static const _measuredCycles = 200;
  static const _batches = 5;

  /// Untimed work before the [round]-th timed cycle.
  void prepare(int round) {}

  /// The timed work of the [round]-th cycle.
  void cycle(int round);

  @override
  void run() {}

  @override
  double measure() {
    setup();
    var round = 0;

    final warmup = Stopwatch()..start();
    while (warmup.elapsed < _warmup) {
      prepare(round);
      cycle(round);
      round++;
    }

    var best = double.infinity;
    for (var batch = 0; batch < _batches; batch++) {
      setup();
      final stopwatch = Stopwatch();
      for (var i = 0; i < _measuredCycles; i++) {
        prepare(round);
        stopwatch.start();
        cycle(round);
        stopwatch.stop();
        round++;
      }
      final perCycle = stopwatch.elapsedMicroseconds / _measuredCycles;
      if (perCycle < best) {
        best = perCycle;
      }
    }

    teardown();
    return best;
  }
}
