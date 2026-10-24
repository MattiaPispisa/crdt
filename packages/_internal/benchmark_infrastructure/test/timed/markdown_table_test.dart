// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';
import 'package:test/test.dart';

void main() {
  group('renderResultsMarkdown', () {
    test('renders one table per source file', () {
      final markdown = renderResultsMarkdown({
        'dag_benchmark.dart': [
          const BenchmarkResult(
            name: 'DAG addNode chain of 1000',
            sourceFile: 'dag_benchmark.dart',
            microseconds: 184.014,
            milliseconds: 0.1840,
            seconds: 0.000184,
          ),
        ],
      });

      expect(markdown, contains('### dag_benchmark.dart'));
      expect(
        markdown,
        contains('| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |'),
      );
      expect(markdown, contains('| --- | --- | --- | --- |'));
      expect(
        markdown,
        contains(
          '| DAG addNode chain of 1000 | 184.0140 | 0.1840 | 0.000184 |',
        ),
      );
    });

    test('keeps subsections in map iteration order', () {
      final markdown = renderResultsMarkdown({
        'b_benchmark.dart': [
          const BenchmarkResult(
            name: 'B',
            sourceFile: 'b_benchmark.dart',
            microseconds: 1,
            milliseconds: 0.001,
            seconds: 0.000001,
          ),
        ],
        'a_benchmark.dart': [
          const BenchmarkResult(
            name: 'A',
            sourceFile: 'a_benchmark.dart',
            microseconds: 1,
            milliseconds: 0.001,
            seconds: 0.000001,
          ),
        ],
      });

      expect(
        markdown.indexOf('### b_benchmark.dart'),
        lessThan(markdown.indexOf('### a_benchmark.dart')),
      );
    });

    test('skips a source file with no results', () {
      final markdown = renderResultsMarkdown({'empty_benchmark.dart': []});

      expect(markdown, isEmpty);
    });
  });

  group('replaceResultSections', () {
    BenchmarkResult result(String sourceFile, String name) => BenchmarkResult(
          name: name,
          sourceFile: sourceFile,
          microseconds: 2,
          milliseconds: 0.002,
          seconds: 0.000002,
        );

    test('replaces the run files and keeps the others, sorted', () {
      final existing = renderResultsMarkdown({
        'b_benchmark.dart': [result('b_benchmark.dart', 'old B')],
        'c_benchmark.dart': [result('c_benchmark.dart', 'C')],
      });

      final merged = replaceResultSections(existing, {
        'b_benchmark.dart': [result('b_benchmark.dart', 'new B')],
        'a_benchmark.dart': [result('a_benchmark.dart', 'A')],
      });

      expect(
        merged,
        renderResultsMarkdown({
          'a_benchmark.dart': [result('a_benchmark.dart', 'A')],
          'b_benchmark.dart': [result('b_benchmark.dart', 'new B')],
          'c_benchmark.dart': [result('c_benchmark.dart', 'C')],
        }),
      );
    });

    test('keeps the old section of a file that produced no results', () {
      final existing = renderResultsMarkdown({
        'a_benchmark.dart': [result('a_benchmark.dart', 'A')],
      });

      expect(
        replaceResultSections(existing, {'a_benchmark.dart': []}),
        existing,
      );
    });
  });
}
