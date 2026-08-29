import 'dart:io';

import 'package:benchmark_infrastructure/src/timed/benchmark_result.dart';
import 'package:benchmark_infrastructure/src/timed/markdown_table.dart';

/// Runs every `benchmarks/src/benchmarks/*_benchmark.dart` file under
/// [packageRoot] and writes the aggregated results to
/// `benchmarks/results.md`.
///
/// Each file runs as its own subprocess — a fresh VM per file, so no
/// benchmark's JIT state or GC pressure leaks into the next one — in
/// alphabetical filename order. A file's stdout is parsed line by line with
/// [BenchmarkResult.tryParse].
///
/// [command] is what launches one file, with the file path appended. The
/// default runs it as a plain script. A benchmark that needs a Flutter binding
/// — anything that builds a widget — passes `['flutter', 'test']` instead.
///
/// [reportUnparsedOutput] echoes every line that is not a result to stderr, so
/// stray output is noticed rather than silently dropped. Turn it off for a
/// [command] that prints progress of its own, such as a test runner, which
/// would otherwise bury the real errors.
Future<void> runTimedBenchmarks({
  required Directory packageRoot,
  List<String> command = const ['dart', 'run'],
  bool reportUnparsedOutput = true,
}) async {
  final benchmarksDir =
      Directory('${packageRoot.path}/benchmarks/src/benchmarks');
  if (!benchmarksDir.existsSync()) {
    stderr.writeln(
      'No benchmarks/src/benchmarks directory found under '
      '${packageRoot.path}',
    );
    return;
  }

  final files = benchmarksDir
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('_benchmark.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final resultsBySourceFile = <String, List<BenchmarkResult>>{};

  for (final file in files) {
    final sourceFile = file.uri.pathSegments.last;
    stdout.writeln('  - 🔄 Running $sourceFile');

    final process = await Process.run(
      command.first,
      [...command.skip(1), file.path],
    );
    if (process.exitCode != 0) {
      stderr
        ..writeln(
          'Benchmark $sourceFile failed with exit code ${process.exitCode}:',
        )
        ..writeln(process.stderr);
      exitCode = 1;
      continue;
    }

    final results = <BenchmarkResult>[];
    for (final line in (process.stdout as String).split('\n')) {
      if (line.trim().isEmpty) {
        continue;
      }
      final result = BenchmarkResult.tryParse(line, sourceFile: sourceFile);
      if (result == null) {
        if (reportUnparsedOutput) {
          stderr.writeln('Unparsed output from $sourceFile: $line');
        }
        continue;
      }
      results.add(result);
    }
    resultsBySourceFile[sourceFile] = results;

    stdout.writeln('  - ✅ Finished $sourceFile');
  }

  final resultsFile = File('${packageRoot.path}/benchmarks/results.md')
    ..writeAsStringSync(renderResultsMarkdown(resultsBySourceFile));

  stdout.writeln('Benchmarks finished. Results are in ${resultsFile.path}');
}
