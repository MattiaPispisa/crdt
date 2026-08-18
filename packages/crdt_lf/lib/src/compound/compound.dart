import 'package:crdt_lf/src/document/document.dart';
import 'package:crdt_lf/src/operation/id.dart';
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
  /// An operation built by folding two others carries the **greater** of their
  /// stamps. The peer that produced them has already folded each one into its
  /// own state with its own stamp; a peer that receives the compound folds it
  /// once, with this one. Since stamps end up **inside** the state, any rule
  /// other than the greater would leave the two peers holding different
  /// values.
  ///
  /// Taking the greater is safe because the operations of one transaction on
  /// one peer are never concurrent with each other: each is stamped after a
  /// clock tick, so the later one always wins.
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
          compound.stamp = _greaterStamp(accumulator.stamp, operation.stamp);
          accumulator = compound;
        }
      } else {
        next(operation);
      }
    }

    next(accumulator);

    return result;
  }

  /// The greater of [a] and [b]; `null` when neither is stamped.
  ///
  /// A handler that does not ask to be stamped folds into an unstamped
  /// operation, exactly as it did before stamps existed.
  static OperationId? _greaterStamp(OperationId? a, OperationId? b) {
    if (a == null) {
      return b;
    }
    if (b == null) {
      return a;
    }
    return a.compareTo(b) >= 0 ? a : b;
  }
}
