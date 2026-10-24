// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

@TestOn('vm')
library;

import 'dart:io';

import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';
import 'package:test/test.dart';

void main() {
  group('parseArguments', () {
    test('include is null without arguments', () {
      expect(parseArguments([]).include, isNull);
    });

    test('stems names and de-duplicates them', () {
      expect(
        parseArguments([
          '--include=delete_handler, dag_benchmark.dart',
          '--include=apply_changes_benchmark,dag',
        ]).include,
        {'delete_handler', 'dag', 'apply_changes'},
      );
    });

    test('refuses an empty list', () {
      expect(
        () => parseArguments(['--include=']),
        throwsFormatException,
      );
    });
  });

  group('runTimedBenchmarks with include', () {
    late Directory root;
    late File results;

    setUp(() {
      root = Directory.systemTemp.createTempSync('runner_test');
      final benchmarks = Directory('${root.path}/benchmarks/src/benchmarks')
        ..createSync(recursive: true);
      for (final name in ['a', 'b']) {
        File('${benchmarks.path}/${name}_benchmark.dart').writeAsStringSync(
          "void main() => print('$benchmarkResultMarker"
          '{"name": "new $name", "microseconds": 1}\');\n',
        );
      }
      results = File('${root.path}/benchmarks/results.md')
        ..writeAsStringSync(
          renderResultsMarkdown({
            for (final name in ['a', 'b'])
              '${name}_benchmark.dart': [
                BenchmarkResult(
                  name: 'old $name',
                  sourceFile: '${name}_benchmark.dart',
                  microseconds: 2,
                  milliseconds: 0.002,
                  seconds: 0.000002,
                ),
              ],
          }),
        );
    });

    tearDown(() {
      exitCode = 0;
      root.deleteSync(recursive: true);
    });

    test('runs only the included files and keeps the other results', () async {
      await runTimedBenchmarks(
        packageRoot: root,
        command: [Platform.resolvedExecutable, 'run'],
        include: {'a'},
      );

      final markdown = results.readAsStringSync();
      expect(markdown, contains('| new a |'));
      expect(markdown, contains('| old b |'));
      expect(markdown, isNot(contains('| old a |')));
    });

    test('refuses an unknown name and runs nothing', () async {
      final before = results.readAsStringSync();

      await runTimedBenchmarks(packageRoot: root, include: {'missing'});

      expect(exitCode, 64);
      expect(results.readAsStringSync(), before);
    });
  });
}
