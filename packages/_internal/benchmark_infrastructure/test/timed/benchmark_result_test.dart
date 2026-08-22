import 'dart:convert';

import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';
import 'package:test/test.dart';

String _resultLine(String name, double microseconds) => '$benchmarkResultMarker'
    '${jsonEncode({'name': name, 'microseconds': microseconds})}';

void main() {
  group('BenchmarkResult.tryParse', () {
    test('parses a CustomEmitter line', () {
      final result = BenchmarkResult.tryParse(
        _resultLine('DAG addNode chain of 1000', 184.014),
        sourceFile: 'dag_benchmark.dart',
      );

      expect(result, isNotNull);
      expect(result!.name, 'DAG addNode chain of 1000');
      expect(result.sourceFile, 'dag_benchmark.dart');
      expect(result.microseconds, closeTo(184.014, 0.001));
      expect(result.milliseconds, closeTo(0.184014, 0.000001));
      expect(result.seconds, closeTo(0.000184014, 0.000000001));
    });

    test(
        'parses a name with characters a hand-rolled format would need to '
        'escape', () {
      final result = BenchmarkResult.tryParse(
        _resultLine(
          'Fugue text takeSnapshot (tombstones: false) | "weird" name',
          1160.754,
        ),
        sourceFile: 'fugue_snapshot_benchmark.dart',
      );

      expect(
        result?.name,
        'Fugue text takeSnapshot (tombstones: false) | "weird" name',
      );
    });

    test('returns null for a line without the marker', () {
      final result = BenchmarkResult.tryParse(
        'not a benchmark line',
        sourceFile: 'dag_benchmark.dart',
      );

      expect(result, isNull);
    });

    test('returns null for the runner progress lines', () {
      final result = BenchmarkResult.tryParse(
        '  - 🔄 Running dag_benchmark.dart',
        sourceFile: 'dag_benchmark.dart',
      );

      expect(result, isNull);
    });
  });
}
