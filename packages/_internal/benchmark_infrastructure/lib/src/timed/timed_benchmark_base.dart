import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:benchmark_infrastructure/src/timed/custom_emitter.dart';

/// A [BenchmarkBase] with a [CustomEmitter] already wired in, so a benchmark
/// only names itself instead of repeating the emitter on every constructor.
abstract class TimedBenchmarkBase extends BenchmarkBase {
  /// Creates a benchmark reported under [name].
  ///
  /// [runsPerMeasure] is forwarded to [CustomEmitter]: pass `1` when
  /// overriding `measure()` to time a fixed number of cycles instead of the
  /// default harness loop.
  TimedBenchmarkBase(super.name, {int runsPerMeasure = 10})
      : super(emitter: CustomEmitter(runsPerMeasure: runsPerMeasure));
}
