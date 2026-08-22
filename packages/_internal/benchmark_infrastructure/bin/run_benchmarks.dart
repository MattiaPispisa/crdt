import 'dart:io';

import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';

/// Runs timed and memory benchmarks for the current package.
///
/// Both run by default. Pass `--no-timed` or `--no-memory` to skip one —
/// e.g. `dart run benchmark_infrastructure:run_benchmarks --no-memory` runs
/// only the (faster, quieter) timed suite.
Future<void> main(List<String> arguments) async {
  if (!arguments.contains('--no-timed')) {
    await runTimedBenchmarks(packageRoot: Directory.current);
  }
  if (!arguments.contains('--no-memory')) {
    await runMemoryBenchmarks(packageRoot: Directory.current);
  }
}
