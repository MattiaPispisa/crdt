import 'dart:io';

import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';
import 'package:test/test.dart';

/// A synchronous benchmark that only counts what the loop asked of it.
///
/// [slowFirstBatch] blocks for a few milliseconds on the very first cycle, so
/// a test can tell a score taken from the fastest batch from a mean.
///
/// Settle cycles are off unless a test asks for them, so a cycle count means
/// the timed cycles alone.
class _CountingBenchmark extends FixedCycleTimedBenchmark {
  _CountingBenchmark({
    super.setupPerBatch = true,
    super.settleCycles = 0,
    this.slowFirstBatch = false,
    this.slowEveryBatch = false,
    this.throwOnRun = false,
  }) : super(
          'counting',
          warmupDuration: Duration.zero,
          measuredCycles: 10,
          batches: 3,
        );

  final bool slowFirstBatch;

  /// Blocks on the first cycle that follows every [setup], which is a settle
  /// cycle whenever there is one.
  final bool slowEveryBatch;

  final bool throwOnRun;

  int setups = 0;
  int runs = 0;
  int teardowns = 0;
  int _runsThisSetup = 0;

  @override
  void setup() {
    setups += 1;
    _runsThisSetup = 0;
  }

  @override
  void run() {
    if (throwOnRun) {
      throw StateError('run failed');
    }
    if ((slowFirstBatch && runs == 0) ||
        (slowEveryBatch && _runsThisSetup == 0)) {
      sleep(const Duration(milliseconds: 20));
    }
    runs += 1;
    _runsThisSetup += 1;
  }

  @override
  void teardown() => teardowns += 1;
}

/// The asynchronous twin of [_CountingBenchmark].
class _AsyncCountingBenchmark extends AsyncFixedCycleTimedBenchmark {
  _AsyncCountingBenchmark({
    super.settleCycles = 0,
    this.slowFirstBatch = false,
  }) : super(
          'async counting',
          warmupDuration: Duration.zero,
          measuredCycles: 10,
          batches: 3,
        );

  final bool slowFirstBatch;

  int setups = 0;
  int runs = 0;
  int teardowns = 0;

  @override
  Future<void> setup() async => setups += 1;

  @override
  Future<void> run() async {
    if (slowFirstBatch && runs == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    } else {
      // A real suspension on every cycle, so the loop is proven to await.
      await Future<void>.delayed(Duration.zero);
    }
    runs += 1;
  }

  @override
  Future<void> teardown() async => teardowns += 1;
}

void main() {
  group('FixedCycleTimedBenchmark', () {
    test('runs exactly batches * measuredCycles cycles', () {
      final benchmark = _CountingBenchmark()..measure();

      expect(benchmark.runs, 30);
      expect(benchmark.teardowns, 1);
    });

    test('sets up once per batch, plus once for the warm-up', () {
      final benchmark = _CountingBenchmark()..measure();

      expect(benchmark.setups, 4);
    });

    test('sets up only once when setupPerBatch is off', () {
      final benchmark = _CountingBenchmark(setupPerBatch: false)..measure();

      expect(benchmark.setups, 1);
      expect(benchmark.runs, 30);
    });

    test('scores the fastest batch, not the mean of all of them', () {
      final score = _CountingBenchmark(slowFirstBatch: true).measure();

      // The slow batch alone costs 20 ms over 10 cycles: 2000 µs per cycle,
      // and a mean over three batches would still be near 667 µs. The other
      // two batches do nothing measurable.
      expect(score, lessThan(100));
    });

    test('runs the settle cycles untimed after each per-batch setup', () {
      final benchmark = _CountingBenchmark(settleCycles: 2)..measure();

      // 3 batches of 10 timed cycles, and 2 settle cycles before each.
      expect(benchmark.runs, 36);
    });

    test('skips the settle cycles when setupPerBatch is off', () {
      final benchmark =
          _CountingBenchmark(setupPerBatch: false, settleCycles: 2)..measure();

      expect(benchmark.runs, 30);
    });

    test('leaves the settle cycles out of the score', () {
      // The slow cycle is the first one of every batch, so it lands in the
      // settle window and must not reach the stopwatch.
      final score = _CountingBenchmark(settleCycles: 1, slowEveryBatch: true)
          .measure();

      expect(score, lessThan(100));
    });

    test('tears down even when a cycle throws', () {
      final benchmark = _CountingBenchmark(throwOnRun: true);

      expect(benchmark.measure, throwsStateError);
      expect(benchmark.teardowns, 1);
    });
  });

  group('AsyncFixedCycleTimedBenchmark', () {
    test('awaits every cycle and tears down once', () async {
      final benchmark = _AsyncCountingBenchmark();
      await benchmark.measure();

      expect(benchmark.runs, 30);
      expect(benchmark.setups, 4);
      expect(benchmark.teardowns, 1);
    });

    test('scores the fastest batch, not the mean of all of them', () async {
      final score =
          await _AsyncCountingBenchmark(slowFirstBatch: true).measure();

      expect(score, lessThan(100));
    });

    test('runs the settle cycles untimed after each per-batch setup', () async {
      final benchmark = _AsyncCountingBenchmark(settleCycles: 2);
      await benchmark.measure();

      // 3 batches of 10 timed cycles, and 2 settle cycles before each.
      expect(benchmark.runs, 36);
    });
  });
}
