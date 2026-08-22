import 'dart:io';

import 'package:benchmark_infrastructure/src/memory/memory_benchmark_result.dart';
import 'package:benchmark_infrastructure/src/memory/memory_markdown_table.dart';

/// Runs every `benchmarks/src/memory/*_benchmark.dart` file under
/// [packageRoot] and writes the aggregated results to
/// `benchmarks/memory_results.md`.
///
/// Each file runs as its own `dart run --enable-vm-service=0
/// --no-pause-isolates-on-exit` subprocess — a fresh VM per file, and the VM
/// service is what `MemoryBenchmarkBase` needs to force a GC and read real
/// isolate heap usage. Port `0` picks an unused port, so back-to-back runs
/// never collide with a service left open by a previous one.
/// `--no-pause-isolates-on-exit` stops the isolate from pausing for a
/// debugger on exit, so the subprocess still terminates on its own once its
/// `main()` returns. A file's stdout is parsed line by line with
/// [MemoryBenchmarkResult.tryParse]; a line that doesn't match — including
/// the VM service's own startup banner — is reported on stderr instead of
/// being silently dropped.
Future<void> runMemoryBenchmarks({required Directory packageRoot}) async {
  final benchmarksDir =
      Directory('${packageRoot.path}/benchmarks/src/memory');
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

    final process = await Process.run('dart', [
      'run',
      '--enable-vm-service=0',
      '--no-pause-isolates-on-exit',
      file.path,
    ]);
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

  final resultsFile = File('${packageRoot.path}/benchmarks/memory_results.md')
    ..writeAsStringSync(renderMemoryResultsMarkdown(resultsBySourceFile));

  stdout.writeln(
    'Memory benchmarks finished. Results are in ${resultsFile.path}',
  );
}
