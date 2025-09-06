import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import '../common/handler_benchmark.dart';

class ORSetHandlerBenchmark
    extends BaseHandlerOperationsBenchmark<CRDTORSetHandler<String>> {
  ORSetHandlerBenchmark({required super.useIncrementalCacheUpdate})
      : super(
          handlerName: 'CRDTORSetHandler',
          handlerFactory: (document) =>
              CRDTORSetHandler<String>(document, 'set'),
        );

  @override
  Set<String> getHandlerValue(CRDTORSetHandler<String> handler) {
    return handler.value;
  }

  @override
  List<VoidCallback> generateOperations(
    CRDTORSetHandler<String> handler,
    int count,
  ) {
    final random = Random(42); // Fixed seed for reproducible results
    final operations = <VoidCallback>[];
    final existingValues = <String>[];

    for (var i = 0; i < count; i++) {
      if (random.nextBool() || existingValues.isEmpty) {
        // Add operation with a new unique value
        final value = 'value_$i';
        existingValues.add(value);
        operations.add(() => handler.add(value));
      } else {
        // Remove operation with an existing value
        final valueIndex = random.nextInt(existingValues.length);
        final value = existingValues.removeAt(valueIndex);
        operations.add(() => handler.remove(value));
      }
    }
    return operations;
  }
}

void main() {
  ORSetHandlerBenchmark(useIncrementalCacheUpdate: true).report();
}
