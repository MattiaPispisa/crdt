import 'dart:io';

import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';

Future<void> main() async {
  await runTimedBenchmarks(packageRoot: Directory.current);
}
