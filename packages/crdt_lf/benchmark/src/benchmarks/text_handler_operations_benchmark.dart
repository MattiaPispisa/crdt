import 'dart:math';

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:crdt_lf/crdt_lf.dart';

import '../common/custom_emitter.dart';

// TODO(mattia): fix this benchmark, add benchmarks for other handlers (create a configurable setup (list of operations to be executed in run with an initial optional snapshot) show time with cache enabled and disabled, decide when value is readed))

/// Benchmark for CRDT text handler operations
/// Tests insertion, update, and deletion operations on text content
class TextHandlerOperationsBenchmark extends BenchmarkBase {
  TextHandlerOperationsBenchmark()
      : super(
          'Text Handler Operations (1000 ops)',
          emitter: const CustomEmitter(),
        );

  late final CRDTDocument doc;
  late final CRDTTextHandler textHandler;
  late final List<_Operation> operations;

  @override
  void setup() {
    doc = CRDTDocument(peerId: PeerId.generate());
    textHandler = CRDTTextHandler(doc, 'text');

    // Initialize with some base content
    textHandler.insert(0, 'Initial text content for testing operations. ');

    // Generate a list of operations to perform
    operations = _generateOperations(1000);
  }

  @override
  void run() {
    // Execute all operations
    for (final operation in operations) {
      switch (operation.type) {
        case _OperationType.insert:
          textHandler.insert(operation.index, operation.text!);
          break;
        case _OperationType.update:
          textHandler.update(operation.index, operation.text!);
          break;
        case _OperationType.delete:
          textHandler.delete(operation.index, operation.count!);
          break;
      }
    }
  }

  /// Generates a list of random operations for benchmarking
  List<_Operation> _generateOperations(int count) {
    final random = Random(42); // Fixed seed for reproducible results
    final operations = <_Operation>[];

    // Sample texts for operations
    const sampleTexts = [
      'Hello ',
      'World! ',
      'CRDT ',
      'Text ',
      'Operations ',
      'Benchmark ',
      'Testing ',
      'Performance ',
      'Insert ',
      'Update ',
      'Delete ',
      'Random ',
      'Content ',
      'Generation ',
      'Algorithm ',
    ];

    for (var i = 0; i < count; i++) {
      final operationType =
          _OperationType.values[random.nextInt(_OperationType.values.length)];
      final currentLength = textHandler.length;

      switch (operationType) {
        case _OperationType.insert:
          final index = currentLength > 0 ? random.nextInt(currentLength) : 0;
          final text = sampleTexts[random.nextInt(sampleTexts.length)];
          operations.add(_Operation(
            type: operationType,
            index: index,
            text: text,
          ));
          break;

        case _OperationType.update:
          if (currentLength > 0) {
            final index = random.nextInt(currentLength);
            final text = sampleTexts[random.nextInt(sampleTexts.length)];
            operations.add(_Operation(
              type: operationType,
              index: index,
              text: text,
            ));
          } else {
            // If no content, insert instead
            operations.add(_Operation(
              type: _OperationType.insert,
              index: 0,
              text: sampleTexts[random.nextInt(sampleTexts.length)],
            ));
          }
          break;

        case _OperationType.delete:
          if (currentLength > 0) {
            final index = random.nextInt(currentLength);
            final maxCount =
                min(5, currentLength - index); // Delete up to 5 characters
            final count = maxCount > 0 ? random.nextInt(maxCount) + 1 : 1;
            operations.add(_Operation(
              type: operationType,
              index: index,
              count: count,
            ));
          } else {
            // If no content, insert instead
            operations.add(_Operation(
              type: _OperationType.insert,
              index: 0,
              text: sampleTexts[random.nextInt(sampleTexts.length)],
            ));
          }
          break;
      }
    }

    return operations;
  }
}

/// Benchmark for text handler state computation
/// Tests the performance of computing the current text state
class TextHandlerStateComputationBenchmark extends BenchmarkBase {
  TextHandlerStateComputationBenchmark()
      : super(
          'Text Handler State Computation',
          emitter: const CustomEmitter(),
        );

  late final CRDTDocument doc;
  late final CRDTTextHandler textHandler;

  @override
  void setup() {
    doc = CRDTDocument(peerId: PeerId.generate());
    textHandler = CRDTTextHandler(doc, 'text');

    // Create a document with many changes to test state computation
    final random = Random(42);
    const sampleTexts = [
      'Lorem ipsum dolor sit amet, consectetur adipiscing elit. ',
      'Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. ',
      'Ut enim ad minim veniam, quis nostrud exercitation ullamco. ',
      'Duis aute irure dolor in reprehenderit in voluptate velit esse. ',
      'Excepteur sint occaecat cupidatat non proident, sunt in culpa. ',
    ];

    // Perform 500 operations to create a complex state
    for (var i = 0; i < 500; i++) {
      final operationType =
          _OperationType.values[random.nextInt(_OperationType.values.length)];
      final currentLength = textHandler.length;

      switch (operationType) {
        case _OperationType.insert:
          final index = currentLength > 0 ? random.nextInt(currentLength) : 0;
          final text = sampleTexts[random.nextInt(sampleTexts.length)];
          textHandler.insert(index, text);
          break;

        case _OperationType.update:
          if (currentLength > 0) {
            final index = random.nextInt(currentLength);
            final text = sampleTexts[random.nextInt(sampleTexts.length)];
            textHandler.update(index, text);
          }
          break;

        case _OperationType.delete:
          if (currentLength > 0) {
            final index = random.nextInt(currentLength);
            final maxCount = min(10, currentLength - index);
            final count = maxCount > 0 ? random.nextInt(maxCount) + 1 : 1;
            textHandler.delete(index, count);
          }
          break;
      }
    }
  }

  @override
  void run() {
    // Force state computation by accessing the value
    final _ = textHandler.value;
  }
}

/// Benchmark for text handler cached state updates
/// Tests the performance of updating cached state with operations
class TextHandlerCachedStateBenchmark extends BenchmarkBase {
  TextHandlerCachedStateBenchmark()
      : super(
          'Text Handler Cached State Updates',
          emitter: const CustomEmitter(),
        );

  late final CRDTDocument doc;
  late final CRDTTextHandler textHandler;

  @override
  void setup() {
    doc = CRDTDocument(peerId: PeerId.generate());
    textHandler = CRDTTextHandler(doc, 'text');

    // Initialize with some content and warm up the cache
    textHandler.insert(0, 'Initial content for cached state testing. ');
    final _ = textHandler.value; // This will cache the state
  }

  @override
  void run() {
    // Perform operations that will update the cached state
    textHandler
      ..insert(0, 'Inserted ')
      ..update(10, 'Updated ')
      ..delete(20, 5);
  }
}

/// Represents a text operation for benchmarking
class _Operation {
  const _Operation({
    required this.type,
    required this.index,
    this.text,
    this.count,
  });

  final _OperationType type;
  final int index;
  final String? text;
  final int? count;
}

/// Types of text operations
enum _OperationType {
  insert,
  update,
  delete,
}

void main() {
  // Run all text handler benchmarks
  // ignore: avoid_print
  print('Running CRDT Text Handler Benchmarks...\n');

  TextHandlerOperationsBenchmark().report();
  // ignore: avoid_print
  print('');

  TextHandlerStateComputationBenchmark().report();
  // ignore: avoid_print
  print('');

  TextHandlerCachedStateBenchmark().report();
}
