import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';

// TODO(mattia): a published PN-counter is tracked by issue #126. Until it
// lands, this one lives in the test suite: it is the only handler that owns an
// operation kind outside the four conventional ones, so it is what keeps
// `OperationType.custom` covered end to end.

/// A counter that converges by summing the deltas every peer contributed.
///
/// Two peers that increment concurrently end up with both increments: a delta
/// is applied once per change, and addition does not care about the order the
/// changes arrive in, which is why [stateIsOrderIndependent] is `true`.
///
/// Its operation kind is [incrementKind], declared with
/// [OperationType.custom]. That value means "increment" for this handler type
/// alone — another handler is free to give the same byte another meaning.
///
/// ```dart
/// final doc = CRDTDocument(peerId: PeerId.generate());
/// final votes = PNCounterHandler(doc, 'votes')
///   ..increment(3)
///   ..decrement();
/// print(votes.value); // 2
/// ```
class PNCounterHandler extends Handler<int> {
  /// Creates a counter addressed by [id] in [doc].
  PNCounterHandler(super.doc, this._id, {super.handlerType});

  /// The binary kind of an increment, the first value past the four
  /// conventional ones.
  static const int incrementKind = 4;

  final String _id;

  @override
  String get id => _id;

  /// The operation type this handler owns.
  late final OperationType incrementType = OperationType.custom(
    this,
    kind: incrementKind,
    name: 'increment',
  );

  @override
  late final OperationFactory operationFactory = _fromBytes;

  Operation? _fromBytes(Uint8List operationBytes) {
    final env = OperationEnvelopeCodec.decode(operationBytes);
    if (env.handlerId != id || env.handlerType != handlerType) {
      return null;
    }

    final body = Uint8List.sublistView(operationBytes, env.bodyOffset);
    if (env.kind == incrementKind) {
      return PNCounterIncrementOperation.fromBodyBytes(this, body);
    }

    throw UnknownOperationKindException(
      handlerType: env.handlerType,
      handlerId: env.handlerId,
      kind: env.kind,
    );
  }

  /// Adds [by] to the counter.
  void increment([int by = 1]) {
    doc.registerOperation(
      PNCounterIncrementOperation(
        id: id,
        type: incrementType,
        delta: by,
      ),
    );
  }

  /// Subtracts [by] from the counter.
  void decrement([int by = 1]) => increment(-by);

  /// The sum of every delta this document has seen.
  int get value {
    final cached = cachedState;
    if (cached != null) {
      return cached;
    }

    var total = _initialValue();
    for (final operation in operations()) {
      if (operation is PNCounterIncrementOperation) {
        total += operation.delta;
      }
    }
    updateCachedState(total);
    return total;
  }

  @override
  bool get stateIsOrderIndependent => true;

  @override
  int? incrementCachedState({
    required Operation operation,
    required int state,
  }) {
    if (operation is PNCounterIncrementOperation) {
      return state + operation.delta;
    }
    return state;
  }

  @override
  Uint8List getSnapshotState() {
    final out = BytesBuilder(copy: false);
    _writeSigned(value, out);
    return out.toBytes();
  }

  int _initialValue() {
    final snapshot = lastSnapshot();
    if (snapshot == null || snapshot.isEmpty) {
      return 0;
    }
    return _readSigned(snapshot, 0);
  }

  @override
  String toString() => 'PNCounterHandler($_id, $value)';
}

/// Adds [delta] to a [PNCounterHandler].
///
/// Body layout: a sign byte (`1` when negative), then the magnitude as a
/// uvarint.
class PNCounterIncrementOperation extends Operation {
  /// Creates an increment of [delta] for the handler addressed by [id].
  const PNCounterIncrementOperation({
    required super.id,
    required super.type,
    required this.delta,
  });

  /// Decodes an increment from the [body] of an envelope addressed to
  /// [handler].
  factory PNCounterIncrementOperation.fromBodyBytes(
    PNCounterHandler handler,
    Uint8List body,
  ) {
    return PNCounterIncrementOperation(
      id: handler.id,
      type: handler.incrementType,
      delta: _readSigned(body, 0),
    );
  }

  /// How much the counter moves.
  final int delta;

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false);
    _writeSigned(delta, out);
    return out.toBytes();
  }

  @override
  Map<String, dynamic> toPayload() {
    return {
      ...super.toPayload(),
      'delta': delta,
    };
  }
}

/// Writes [value] as a sign byte followed by a uvarint magnitude.
///
/// [UVarint] refuses negative numbers, and a counter has to move both ways.
void _writeSigned(int value, BytesBuilder out) {
  out.addByte(value < 0 ? 1 : 0);
  UVarint.write(value.abs(), out);
}

int _readSigned(Uint8List bytes, int offset) {
  if (offset >= bytes.length) {
    throw const FormatException('Truncated PN-counter delta');
  }
  final negative = bytes[offset] != 0;
  final magnitude = UVarint.read(bytes, offset: offset + 1).value;
  return negative ? -magnitude : magnitude;
}
