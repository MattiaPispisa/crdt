import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import '../common/handler_benchmark.dart';

typedef VoidCallback = void Function();

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

  /// Generates a list of random operations for benchmarking
  @override
  List<VoidCallback> generateOperations(
    CRDTTextHandler textHandler,
    int count,
  ) {
    final random = Random(42); // Fixed seed for reproducible results
    final operations = <VoidCallback>[];

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

    for (var i = 0; i < count; i++) {
      final operationType =
          operationTypes[random.nextInt(operationTypes.length)];
      final currentLength = textHandler.length;

      switch (operationType) {
        case 'insert':
          final index = currentLength > 0 ? random.nextInt(currentLength) : 0;
          final text = sampleTexts[random.nextInt(sampleTexts.length)];
          operations.add(() => textHandler.insert(index, text));
          break;

        case 'update':
          if (currentLength > 0) {
            final index = random.nextInt(currentLength);
            final text = sampleTexts[random.nextInt(sampleTexts.length)];
            operations.add(() => textHandler.update(index, text));
          } else {
            // If no content, insert instead
            operations.add(
              () => textHandler.insert(
                0,
                sampleTexts[random.nextInt(sampleTexts.length)],
              ),
            );
          }
          break;

        case 'delete':
          if (currentLength > 0) {
            final index = random.nextInt(currentLength);
            final maxCount =
                min(5, currentLength - index); // Delete up to 5 characters
            final count = maxCount > 0 ? random.nextInt(maxCount) + 1 : 1;
            operations.add(() => textHandler.delete(index, count));
          } else {
            // If no content, insert instead
            operations.add(
              () => textHandler.insert(
                0,
                sampleTexts[random.nextInt(sampleTexts.length)],
              ),
            );
          }
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
