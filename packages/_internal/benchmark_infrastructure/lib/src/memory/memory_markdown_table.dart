import 'package:benchmark_infrastructure/src/memory/memory_benchmark_result.dart';

/// Renders [resultsBySourceFile] as GitHub-Flavored Markdown.
///
/// Produces one `###` subsection per source file, each with its own results
/// table (header + delimiter row + one row per benchmark), so a change to a
/// single benchmark file only touches its own subsection of the rendered
/// output. Subsections and rows keep the iteration order of
/// [resultsBySourceFile] and its lists — the caller decides that order.
String renderMemoryResultsMarkdown(
  Map<String, List<MemoryBenchmarkResult>> resultsBySourceFile,
) {
  final buffer = StringBuffer();

  resultsBySourceFile.forEach((sourceFile, results) {
    if (results.isEmpty) {
      return;
    }

    buffer
      ..writeln('### $sourceFile')
      ..writeln()
      ..writeln('| Benchmark | Memory (B) | Memory (KB) | Memory (MB) |')
      ..writeln('| --- | --- | --- | --- |');

    for (final result in results) {
      buffer.writeln(
        '| ${result.name} '
        '| ${result.bytes} '
        '| ${result.kilobytes.toStringAsFixed(4)} '
        '| ${result.megabytes.toStringAsFixed(6)} |',
      );
    }

    buffer.writeln();
  });

  return buffer.toString();
}
