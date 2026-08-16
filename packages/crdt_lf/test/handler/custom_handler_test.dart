import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

import '../helpers/pn_counter_handler.dart';

void main() {
  group('a handler that declares its own operation kind', () {
    test('sums the deltas it is given', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final counter = PNCounterHandler(doc, 'counter')
        ..increment(3)
        ..increment()
        ..decrement(2);

      expect(counter.value, equals(2));
    });

    test('writes its kind into the envelope and reads it back', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final counter = PNCounterHandler(doc, 'counter')..increment(300);

      final change = doc.exportChanges().single;
      final envelope = OperationEnvelopeCodec.decode(change.payloadBytes());
      expect(envelope.kind, equals(PNCounterHandler.incrementKind));
      expect(envelope.kind, greaterThan(OperationType.kindMove));

      final operation = counter.operationFactory(change.payloadBytes());
      expect(operation, isA<PNCounterIncrementOperation>());
      expect((operation! as PNCounterIncrementOperation).delta, equals(300));
    });

    test('round-trips a negative delta', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final counter = PNCounterHandler(doc, 'counter')..decrement(1000);

      final change = doc.exportChanges().single;
      final operation = counter.operationFactory(change.payloadBytes())!
          as PNCounterIncrementOperation;

      expect(operation.delta, equals(-1000));
    });

    test('concurrent increments from two peers all survive', () {
      final a = CRDTDocument(peerId: PeerId.generate());
      final b = CRDTDocument(peerId: PeerId.generate());
      final counterA = PNCounterHandler(a, 'counter');
      final counterB = PNCounterHandler(b, 'counter');

      counterA.increment(10);
      counterB
        ..increment(4)
        ..decrement();

      b.importChanges(a.exportChanges());
      a.importChanges(b.exportChanges());

      expect(counterA.value, equals(13));
      expect(counterB.value, equals(13));
    });

    test('survives a snapshot of its own state', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final counter = PNCounterHandler(doc, 'counter')
        ..increment(7)
        ..decrement(9);
      final snapshot = doc.takeSnapshot();

      final restored = CRDTDocument(peerId: PeerId.generate());
      final restoredCounter = PNCounterHandler(restored, 'counter');
      restored
        ..importSnapshot(snapshot)
        ..importChanges(doc.exportChanges());

      expect(restoredCounter.value, equals(counter.value));
      expect(restoredCounter.value, equals(-2));
    });

    test('two handlers may give the same kind two meanings', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final counter = PNCounterHandler(doc, 'counter')
        ..increment(5)
        ..increment(3);
      final marker = _MarkerHandler(doc, 'marker')
        ..set(5)
        ..set(3);

      // Same byte on the wire, read through the handler type that precedes it.
      expect(
        _MarkerHandler.setKind,
        equals(PNCounterHandler.incrementKind),
      );
      expect(counter.value, equals(8));
      expect(marker.value, equals(3));
    });

    test("a change for the other handler is not this handler's to decode", () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final counter = PNCounterHandler(doc, 'counter');
      final marker = _MarkerHandler(doc, 'marker')..set(42);

      final change = doc.exportChanges().single;
      // Same kind byte, different handler type: not mine, and not an error.
      expect(counter.operationFactory(change.payloadBytes()), isNull);
      expect(marker.operationFactory(change.payloadBytes()), isNotNull);
    });
  });
}

/// Holds the last value it was set to, under the same kind byte the
/// PN-counter uses for an increment.
class _MarkerHandler extends Handler<int> {
  _MarkerHandler(super.doc, this._id);

  static const int setKind = 4;

  final String _id;

  @override
  String get id => _id;

  late final OperationType setType = OperationType.custom(
    this,
    kind: setKind,
    name: 'set',
  );

  @override
  late final OperationFactory operationFactory = _fromBytes;

  Operation? _fromBytes(Uint8List operationBytes) {
    final env = OperationEnvelopeCodec.decode(operationBytes);
    if (env.handlerId != id || env.handlerType != handlerType) {
      return null;
    }

    final body = Uint8List.sublistView(operationBytes, env.bodyOffset);
    if (env.kind == setKind) {
      return _MarkerSetOperation(
        id: id,
        type: setType,
        value: UVarint.read(body, offset: 0).value,
      );
    }

    throw UnknownOperationKindException(
      handlerType: env.handlerType,
      handlerId: env.handlerId,
      kind: env.kind,
    );
  }

  void set(int value) {
    doc.registerOperation(
      _MarkerSetOperation(id: id, type: setType, value: value),
    );
  }

  int get value {
    var current = 0;
    for (final operation in operations()) {
      if (operation is _MarkerSetOperation) {
        current = operation.value;
      }
    }
    return current;
  }

  @override
  Uint8List getSnapshotState() {
    final out = BytesBuilder(copy: false);
    UVarint.write(value, out);
    return out.toBytes();
  }
}

class _MarkerSetOperation extends Operation {
  const _MarkerSetOperation({
    required super.id,
    required super.type,
    required this.value,
  });

  final int value;

  @override
  Uint8List toBodyBytes() {
    final out = BytesBuilder(copy: false);
    UVarint.write(value, out);
    return out.toBytes();
  }
}
