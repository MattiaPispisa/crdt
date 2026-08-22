import 'dart:io';

import 'package:benchmark_infrastructure/src/memory/memory_benchmark_result.dart';
import 'package:benchmark_infrastructure/src/memory/memory_markdown_table.dart';

/// Runs every `benchmarks/src/memory/*_benchmark.dart` file under
/// [packageRoot] and writes the aggregated results to
/// `benchmarks/memory_results.md`.
///
/// Each file runs as its own `dart run` subprocess — a fresh VM per file, so
/// no benchmark's GC pressure leaks into the next one.
/// 
/// A file's stdout is parsed line by line with
/// [MemoryBenchmarkResult.tryParse]; a line that doesn't match is reported
/// on stderr instead of being silently dropped.
///
/// The results file is left untouched when no file produced a result, so a
/// run that fails outright can't wipe the committed baseline.
Future<void> runMemoryBenchmarks({required Directory packageRoot}) async {
  final benchmarksDir = Directory('${packageRoot.path}/benchmarks/src/memory');
  if (!benchmarksDir.existsSync()) {
    stderr.writeln(
      'No benchmarks/src/memory directory found under ${packageRoot.path}',
    );
    return;
  }

  final files = benchmarksDir
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('_benchmark.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final resultsBySourceFile = <String, List<MemoryBenchmarkResult>>{};

  for (final file in files) {
    final sourceFile = file.uri.pathSegments.last;
    stdout.writeln('  - 🔄 Running $sourceFile (memory)');

    final process = await Process.run('dart', ['run', file.path]);
    if (process.exitCode != 0) {
      stderr
        ..writeln(
          'Memory benchmark $sourceFile failed with exit code '
          '${process.exitCode}:',
        )
        ..writeln(process.stderr);
      exitCode = 1;
      continue;
    }

    final results = <MemoryBenchmarkResult>[];
    for (final line in (process.stdout as String).split('\n')) {
      if (line.trim().isEmpty) {
        continue;
      }
      final result = MemoryBenchmarkResult.tryParse(
        line,
        sourceFile: sourceFile,
      );
      if (result == null) {
        stderr.writeln('Unparsed output from $sourceFile: $line');
        continue;
      }
      results.add(result);
    }
    resultsBySourceFile[sourceFile] = results;

    stdout.writeln('  - ✅ Finished $sourceFile (memory)');
  }

  if (resultsBySourceFile.values.every((results) => results.isEmpty)) {
    stderr.writeln(
      'No memory benchmark results collected. '
      'benchmarks/memory_results.md left unchanged.',
    );
    return;
  }

  final resultsFile = File('${packageRoot.path}/benchmarks/memory_results.md')
    ..writeAsStringSync(renderMemoryResultsMarkdown(resultsBySourceFile));

  stdout.writeln(
    'Memory benchmarks finished. Results are in ${resultsFile.path}',
  );
}
