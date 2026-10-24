// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';

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
    include: parsed.include,
  );
}
