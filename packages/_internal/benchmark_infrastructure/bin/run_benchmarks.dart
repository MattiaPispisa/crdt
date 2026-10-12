import 'dart:io';

import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';

Future<void> main(List<String> arguments) async {
  final Set<String>? include;
  try {
    include = parseIncludeArgument(arguments);
  } on FormatException catch (error) {
    stderr
      ..writeln(error.message)
      ..writeln(runnerUsage);
    exitCode = 64;
    return;
  }
  await runTimedBenchmarks(packageRoot: Directory.current, include: include);
}
