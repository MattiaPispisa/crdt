import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import '../common/handler_benchmark.dart';

/// [BaseHandlerOperationsBenchmark] for [CRDTTextHandler]
class TextHandlerOperationsBenchmark
    extends BaseHandlerOperationsBenchmark<CRDTTextHandler> {
  /// Creates a new [TextHandlerOperationsBenchmark]
  TextHandlerOperationsBenchmark({
    required super.useIncrementalCacheUpdate,
  }) : super(
          handlerName: 'CRDTTextHandler',
          handlerFactory: (document) => CRDTTextHandler(document, 'text'),
        );

  @override
  String getHandlerValue(CRDTTextHandler handler) {
    return handler.value;
  }

  /// Generates a list of random operations for benchmarking.
  ///
  /// The text length is simulated while generating so that indexes are
  /// always valid for the state produced by the previous operations.
  @override
  List<HandlerOperation<CRDTTextHandler>> generateOperations(int count) {
    final random = Random(42); // Fixed seed for reproducible results
    final operations = <HandlerOperation<CRDTTextHandler>>[];

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

    final operationTypes = ['insert', 'update', 'delete'];
    var currentLength = 0;

    for (var i = 0; i < count; i++) {
      var operationType = operationTypes[random.nextInt(operationTypes.length)];
      if (currentLength == 0) {
        // If no content, insert instead
        operationType = 'insert';
      }

      switch (operationType) {
        case 'insert':
          final index = currentLength > 0 ? random.nextInt(currentLength) : 0;
          final text = sampleTexts[random.nextInt(sampleTexts.length)];
          operations.add((handler) => handler.insert(index, text));
          currentLength += text.length;
          break;

        case 'update':
          final index = random.nextInt(currentLength);
          final text = sampleTexts[random.nextInt(sampleTexts.length)];
          operations.add((handler) => handler.update(index, text));
          break;

        case 'delete':
          final index = random.nextInt(currentLength);
          final maxCount =
              min(5, currentLength - index); // Delete up to 5 characters
          final count = maxCount > 0 ? random.nextInt(maxCount) + 1 : 1;
          operations.add((handler) => handler.delete(index, count));
          currentLength -= count;
          break;
      }
    }

    return operations;
  }
}

void main() {
  TextHandlerOperationsBenchmark(useIncrementalCacheUpdate: true).report();
  TextHandlerOperationsBenchmark(useIncrementalCacheUpdate: false).report();
}
