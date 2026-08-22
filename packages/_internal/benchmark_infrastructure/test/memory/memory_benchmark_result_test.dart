import 'dart:convert';

import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';
import 'package:test/test.dart';

String _resultLine(String name, int bytes) => '$memoryResultMarker'
    '${jsonEncode({'name': name, 'bytes': bytes})}';

void main() {
  group('MemoryBenchmarkResult.tryParse', () {
    test('parses a PrintMemoryEmitter line', () {
      final result = MemoryBenchmarkResult.tryParse(
        _resultLine('FugueTree insert 1000 chars', 2097152),
        sourceFile: 'fugue_tree_benchmark.dart',
      );

      expect(result, isNotNull);
      expect(result!.name, 'FugueTree insert 1000 chars');
      expect(result.sourceFile, 'fugue_tree_benchmark.dart');
      expect(result.bytes, 2097152);
      expect(result.kilobytes, closeTo(2048, 0.001));
      expect(result.megabytes, closeTo(2, 0.000001));
    });

    test(
        'parses a name with characters a hand-rolled format would need to '
        'escape', () {
      final result = MemoryBenchmarkResult.tryParse(
        _resultLine(
          'Fugue text takeSnapshot (tombstones: false) | "weird" name',
          1024,
        ),
        sourceFile: 'fugue_snapshot_benchmark.dart',
      );

      expect(
        result?.name,
        'Fugue text takeSnapshot (tombstones: false) | "weird" name',
      );
    });

    test('returns null for a line without the marker', () {
      final result = MemoryBenchmarkResult.tryParse(
        'not a benchmark line',
        sourceFile: 'fugue_tree_benchmark.dart',
      );

      expect(result, isNull);
    });

    test('returns null for the runner progress lines', () {
      final result = MemoryBenchmarkResult.tryParse(
        '  - 🔄 Running fugue_tree_benchmark.dart (memory)',
        sourceFile: 'fugue_tree_benchmark.dart',
      );

      expect(result, isNull);
    });
  });
}
