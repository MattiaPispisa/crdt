import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import '../common/handler_benchmark.dart';

class ListHandlerBenchmark
    extends BaseHandlerOperationsBenchmark<CRDTListHandler<String>> {
  ListHandlerBenchmark({required super.useIncrementalCacheUpdate})
      : super(
          handlerName: 'CRDTListHandler',
          handlerFactory: (document) =>
              CRDTListHandler<String>(document, 'list'),
        );

  @override
  List<String> getHandlerValue(CRDTListHandler<String> handler) {
    return handler.value;
  }

  @override
  List<HandlerOperation<CRDTListHandler<String>>> generateOperations(
    int count,
  ) {
    final random = Random(42); // Fixed seed for reproducible results
    final operations = <HandlerOperation<CRDTListHandler<String>>>[];
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
  ListHandlerBenchmark(useIncrementalCacheUpdate: true).report();
}
