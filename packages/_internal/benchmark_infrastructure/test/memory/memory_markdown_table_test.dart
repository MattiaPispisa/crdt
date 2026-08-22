import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';
import 'package:test/test.dart';

void main() {
  group('renderMemoryResultsMarkdown', () {
    test('renders one table per source file', () {
      final markdown = renderMemoryResultsMarkdown({
        'fugue_tree_benchmark.dart': [
          const MemoryBenchmarkResult(
            name: 'FugueTree insert 1000 chars',
            sourceFile: 'fugue_tree_benchmark.dart',
            bytes: 2097152,
            kilobytes: 2048,
            megabytes: 2,
          ),
        ],
      });

      expect(markdown, contains('### fugue_tree_benchmark.dart'));
      expect(
        markdown,
        contains('| Benchmark | Memory (B) | Memory (KB) | Memory (MB) |'),
      );
      expect(markdown, contains('| --- | --- | --- | --- |'));
      expect(
        markdown,
        contains(
          '| FugueTree insert 1000 chars | 2097152 | 2048.0000 | 2.000000 |',
        ),
      );
    });

    test('keeps subsections in map iteration order', () {
      final markdown = renderMemoryResultsMarkdown({
        'b_benchmark.dart': [
          const MemoryBenchmarkResult(
            name: 'B',
            sourceFile: 'b_benchmark.dart',
            bytes: 1024,
            kilobytes: 1,
            megabytes: 0.001,
          ),
        ],
        'a_benchmark.dart': [
          const MemoryBenchmarkResult(
            name: 'A',
            sourceFile: 'a_benchmark.dart',
            bytes: 1024,
            kilobytes: 1,
            megabytes: 0.001,
          ),
        ],
      });

      expect(
        markdown.indexOf('### b_benchmark.dart'),
        lessThan(markdown.indexOf('### a_benchmark.dart')),
      );
    });

    test('skips a source file with no results', () {
      final markdown =
          renderMemoryResultsMarkdown({'empty_benchmark.dart': []});

      expect(markdown, isEmpty);
    });
  });
}
