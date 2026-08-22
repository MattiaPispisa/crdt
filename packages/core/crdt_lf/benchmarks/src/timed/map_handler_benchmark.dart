import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import '../common/handler_benchmark.dart';

class MapHandlerBenchmark
    extends BaseHandlerOperationsBenchmark<CRDTMapHandler<String>> {
  MapHandlerBenchmark({required super.useIncrementalCacheUpdate})
      : super(
          handlerName: 'CRDTMapHandler',
          handlerFactory: (document) => CRDTMapHandler<String>(document, 'map'),
        );

  @override
  Map<String, String> getHandlerValue(CRDTMapHandler<String> handler) {
    return handler.value;
  }

  @override
  List<HandlerOperation<CRDTMapHandler<String>>> generateOperations(
    int count,
  ) {
    final random = Random(42); // Fixed seed for reproducible results
    final operations = <HandlerOperation<CRDTMapHandler<String>>>[];

    for (var i = 0; i < count; i++) {
      final key = 'key_${random.nextInt(100)}';
      final choice = random.nextInt(3);
      if (choice == 0) {
        operations.add((handler) => handler.set(key, 'value_$i'));
      } else if (choice == 1) {
        operations.add((handler) => handler.update(key, 'updated_$i'));
      } else {
        operations.add((handler) => handler.delete(key));
      }
    }
    return operations;
  }
}

void main() {
  MapHandlerBenchmark(useIncrementalCacheUpdate: true).report();
}
