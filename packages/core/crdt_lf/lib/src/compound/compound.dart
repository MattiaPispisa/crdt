import 'package:crdt_lf/src/document/document.dart';
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
  ///
  /// ## A stamped kind is never folded
  ///
  /// Operations of a kind that reads [Operation.stamp] are left alone, and a
  /// `compound` that folds one anyway fails an assertion in debug.
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
      final handler = _handlers[operation.id];
      if (operation.id != accumulator.id || handler == null) {
        next(operation);
        continue;
      }

      // A compound is one change and carries one id,
      // so folding several stamped operations would replace their marks
      // with a single one, and the peers that already
      // folded them separately would keep resolving conflicts by the old marks.
      if (accumulator.type.stamped || operation.type.stamped) {
        assert(
          handler.compound(accumulator, operation) == null,
          'A stamped kind cannot compound: the compound would be one change '
          'with one id, where the local fold used one per operation.',
        );
        next(operation);
        continue;
      }

      final compound = handler.compound(accumulator, operation);
      if (compound == null) {
        next(operation);
      } else {
        // A fresh operation has no id yet and takes the later one. A handler
        // is also free to hand back one of the two it was given, and that one
        // already carries its own — which the write-once setter would refuse
        // to replace anyway.
        compound.stamp ??= operation.stamp;
        accumulator = compound;
      }
    }

    next(accumulator);

    return result;
  }
}
