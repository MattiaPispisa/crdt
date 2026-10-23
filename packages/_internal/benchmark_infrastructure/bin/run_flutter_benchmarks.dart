import 'dart:io';

import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';

/// Runs the benchmarks of a Flutter package.
///
/// A benchmark that builds a widget needs a Flutter test binding, so each file
/// runs under `flutter test` rather than as a plain script. That runner prints
/// progress of its own, which is why the unparsed-line echo is off.
Future<void> main(List<String> arguments) async {
  final RunnerArguments parsed;
  try {
    parsed = parseArguments(arguments);
  } on FormatException catch (error) {
    stderr
      ..writeln(error.message)
      ..writeln(runnerUsage);
    exitCode = 64;
    return;
  }
  await runTimedBenchmarks(
    packageRoot: Directory.current,
    command: ['flutter', 'test'],
    reportUnparsedOutput: false,
    include: parsed.include,
  );
}
