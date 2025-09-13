import 'package:crdt_lf/src/handler/handler.dart';
import 'package:crdt_lf/src/operation/operation.dart';

/// Compound takes a list of [Operation] and compact them.
class Compound {
  /// Create a [Compound] instance
  Compound({
    required List<Operation> operations,
    required Map<String, Handler<dynamic>> handlers,
  })  : _handlers = handlers,
        _operations = operations;

  final List<Operation> _operations;
  final Map<String, Handler<dynamic>> _handlers;

  /// Compact the operations
  List<Operation> compact() {
    if (_operations.isEmpty) {
      return [];
    }

    final result = <Operation>[];
    var accumulator = _operations.first;

    void next(Operation operation) {
      result.add(accumulator);
      accumulator = operation;
    }

    for (final operation in _operations.skip(1)) {
      if (operation.id == accumulator.id && _handlers[operation.id] != null) {
        final compound =
            _handlers[operation.id]!.compound(accumulator, operation);

        if (compound == null) {
          next(operation);
        } else {
          accumulator = compound;
        }
      } else {
        next(operation);
      }
    }

    next(accumulator);

    return result;
  }
}
