import 'dart:convert';

import 'package:benchmark_infrastructure/src/timed/benchmark_result.dart';

/// Renders [resultsBySourceFile] as GitHub-Flavored Markdown.
///
/// Produces one `###` subsection per source file, each with its own results
/// table (header + delimiter row + one row per benchmark), so a change to a
/// single benchmark file only touches its own subsection of the rendered
/// output. Subsections and rows keep the iteration order of
/// [resultsBySourceFile] and its lists — the caller decides that order.
String renderResultsMarkdown(
  Map<String, List<BenchmarkResult>> resultsBySourceFile,
) {
  final buffer = StringBuffer();

  resultsBySourceFile.forEach((sourceFile, results) {
    if (results.isEmpty) {
      return;
    }

    buffer
      ..writeln('### $sourceFile')
      ..writeln()
      ..writeln('| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |')
      ..writeln('| --- | --- | --- | --- |');

    for (final result in results) {
      buffer.writeln(
        '| ${result.name} '
        '| ${result.microseconds.toStringAsFixed(4)} '
        '| ${result.milliseconds.toStringAsFixed(4)} '
        '| ${result.seconds.toStringAsFixed(6)} |',
      );
    }

    buffer.writeln();
  });

  return buffer.toString();
}

/// Replaces, in [existing], the subsections of the source files in
/// [resultsBySourceFile], and keeps every other subsection as it is.
///
/// Subsections come out sorted by source file, as a full run writes them.
String replaceResultSections(
  String existing,
  Map<String, List<BenchmarkResult>> resultsBySourceFile,
) {
  final sections = <String, String>{
    for (final chunk in existing.split(RegExp('^(?=### )', multiLine: true)))
      if (chunk.startsWith('### '))
        const LineSplitter().convert(chunk).first.substring(4).trim(): chunk,
  };

  resultsBySourceFile.forEach((sourceFile, results) {
    if (results.isNotEmpty) {
      sections[sourceFile] = renderResultsMarkdown({sourceFile: results});
    }
  });

  final sorted = sections.keys.toList()..sort();
  return [for (final sourceFile in sorted) sections[sourceFile]].join();
}
