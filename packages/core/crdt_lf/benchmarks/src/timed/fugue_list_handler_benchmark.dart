import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import '../common/handler_benchmark.dart';

class FugueListHandlerBenchmark
    extends BaseHandlerOperationsBenchmark<CRDTFugueListHandler<String>> {
  FugueListHandlerBenchmark({required super.useIncrementalCacheUpdate})
      : super(
          handlerName: 'CRDTFugueListHandler',
          handlerFactory: (document) =>
              CRDTFugueListHandler<String>(document, 'list'),
        );

  @override
  List<String> getHandlerValue(CRDTFugueListHandler<String> handler) {
    return handler.value;
  }

  @override
  List<HandlerOperation<CRDTFugueListHandler<String>>> generateOperations(
    int count,
  ) {
    final random = Random(42); // Fixed seed for reproducible results
    final operations = <HandlerOperation<CRDTFugueListHandler<String>>>[];
    var length = 0;

    for (var i = 0; i < count; i++) {
      final choice = random.nextInt(3);
      if (choice == 0 || length == 0) {
        final index = random.nextInt(length + 1);
        operations.add((handler) => handler.insert(index, 'item_$i'));
        length++;
      } else if (choice == 1) {
        final index = random.nextInt(length);
        operations.add((handler) => handler.delete(index, 1));
        length--;
      } else {
        final index = random.nextInt(length);
        operations.add((handler) => handler.update(index, 'updated_$i'));
      }
    }
    return operations;
  }
}

void main() {
  FugueListHandlerBenchmark(useIncrementalCacheUpdate: true).report();
}
