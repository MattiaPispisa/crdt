import 'package:benchmark_infrastructure/src/timed/async_timed_benchmark_base.dart';
import 'package:benchmark_infrastructure/src/timed/timed_benchmark_base.dart';

/// Default warm-up length shared by both fixed-cycle bases.
const _defaultWarmup = Duration(milliseconds: 400);

/// Default timed cycles per batch.
const _defaultMeasuredCycles = 200;

/// Default number of batches the score is taken over.
const _defaultBatches = 5;

/// A [TimedBenchmarkBase] that times a fixed number of cycles instead of "as
/// many cycles as fit in two seconds".
///
/// Use it when a cycle **grows** what it measures: one more character in the
/// document, one more change in the history. The default harness loop keeps
/// going until two seconds have passed, so it ends up scoring a document many
/// times the size [setup] built, by a factor that depends on how fast the
/// machine is. Here the count is fixed, so the score describes the size the
/// benchmark's name promises.
///
/// The loop runs [batches] batches of [measuredCycles] cycles each and reports
/// the **fastest** batch. A garbage collection or a scheduler pause can only
/// make a batch slower, so the minimum is the closest reading of what the code
/// costs. A mean lets one unlucky pause move a score by a third — more than
/// the differences these benchmarks usually compare.
///
/// Warm-up is a [Duration], not a cycle count, because workloads sit orders of
/// magnitude apart and a count that warms one leaves the other cold. It
/// matters more than it looks: one text benchmark reported 26 µs after 20
/// warm-up cycles and under 4 µs fully warm — the first number was mostly
/// unoptimized code.
///
/// With [setupPerBatch] on, [setup] runs again before each timed batch, so
/// neither the warm-up nor the batch before it drifts the size away from the
/// name.
///
/// See [AsyncFixedCycleTimedBenchmark] for a cycle that cannot be
/// synchronous.
abstract class FixedCycleTimedBenchmark extends TimedBenchmarkBase {
  /// Creates a benchmark reported under [name].
  FixedCycleTimedBenchmark(
    super.name, {
    this.warmupDuration = _defaultWarmup,
    this.measuredCycles = _defaultMeasuredCycles,
    this.batches = _defaultBatches,
    this.setupPerBatch = true,
  }) : super(runsPerMeasure: 1);

  /// How long to run before timing anything.
  final Duration warmupDuration;

  /// Timed cycles per batch.
  final int measuredCycles;

  /// How many batches the score is taken over. The fastest one wins.
  final int batches;

  /// Whether [setup] runs again before each timed batch.
  final bool setupPerBatch;

  @override
  double measure() {
    try {
      setup();

      final warmup = Stopwatch()..start();
      while (warmup.elapsed < warmupDuration) {
        run();
      }

      var best = double.infinity;
      for (var batch = 0; batch < batches; batch += 1) {
        if (setupPerBatch) {
          setup();
        }

        final stopwatch = Stopwatch()..start();
        for (var cycle = 0; cycle < measuredCycles; cycle += 1) {
          run();
        }
        stopwatch.stop();

        final perCycle = stopwatch.elapsedMicroseconds / measuredCycles;
        if (perCycle < best) {
          best = perCycle;
        }
      }

      return best;
    } finally {
      teardown();
    }
  }
}

/// The asynchronous counterpart of [FixedCycleTimedBenchmark]: same loop, same
/// reasons, for a cycle that has to await.
///
/// A widget benchmark ending its cycle with `await tester.pump()` cannot be
/// written against the synchronous base, whose `run()` returns `void`.
abstract class AsyncFixedCycleTimedBenchmark extends AsyncTimedBenchmarkBase {
  /// Creates a benchmark reported under [name].
  AsyncFixedCycleTimedBenchmark(
    super.name, {
    this.warmupDuration = _defaultWarmup,
    this.measuredCycles = _defaultMeasuredCycles,
    this.batches = _defaultBatches,
    this.setupPerBatch = true,
  });

  /// How long to run before timing anything.
  final Duration warmupDuration;

  /// Timed cycles per batch.
  final int measuredCycles;

  /// How many batches the score is taken over. The fastest one wins.
  final int batches;

  /// Whether [setup] runs again before each timed batch.
  final bool setupPerBatch;

  // The loop below repeats FixedCycleTimedBenchmark.measure on purpose.
  // Sharing one helper over a `FutureOr<void> Function()` would put an await
  // inside the synchronous hot loop, and that await is part of what the
  // synchronous base measures.
  @override
  Future<double> measure() async {
    try {
      await setup();

      final warmup = Stopwatch()..start();
      while (warmup.elapsed < warmupDuration) {
        await run();
      }

      var best = double.infinity;
      for (var batch = 0; batch < batches; batch += 1) {
        if (setupPerBatch) {
          await setup();
        }

        final stopwatch = Stopwatch()..start();
        for (var cycle = 0; cycle < measuredCycles; cycle += 1) {
          await run();
        }
        stopwatch.stop();

        final perCycle = stopwatch.elapsedMicroseconds / measuredCycles;
        if (perCycle < best) {
          best = perCycle;
        }
      }

      return best;
    } finally {
      await teardown();
    }
  }
}
