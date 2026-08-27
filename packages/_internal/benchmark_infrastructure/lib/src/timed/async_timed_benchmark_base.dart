import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:benchmark_infrastructure/src/timed/custom_emitter.dart';
import 'package:benchmark_infrastructure/src/timed/timed_benchmark_base.dart';

/// An [AsyncBenchmarkBase] with a [CustomEmitter] already wired in: the
/// asynchronous counterpart of [TimedBenchmarkBase].
///
/// Use it when one cycle cannot be synchronous. The synchronous base
/// measures a `void run()` — its `exercise` and `measureFor` take a plain
/// `void Function()` — so anything that has to await, such as a widget
/// benchmark ending its cycle with `await tester.pump()`, cannot be written
/// that way.
///
abstract class AsyncTimedBenchmarkBase extends AsyncBenchmarkBase {
  /// Creates a benchmark reported under [name].
  ///
  /// [runsPerMeasure] is forwarded to [CustomEmitter]. It defaults to `1`
  /// because [AsyncBenchmarkBase.exercise] invokes `run()` once, where the
  /// synchronous base invokes it ten times.
  AsyncTimedBenchmarkBase(super.name, {int runsPerMeasure = 1})
      : super(emitter: CustomEmitter(runsPerMeasure: runsPerMeasure));
}
