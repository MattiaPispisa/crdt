import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

import '../helpers/handler.dart';
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

      final operation = counter.operations().single;
      expect(operation, isA<PNCounterIncrementOperation>());
      expect((operation as PNCounterIncrementOperation).delta, equals(300));
    });

    test('round-trips a negative delta', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final counter = PNCounterHandler(doc, 'counter')..decrement(1000);

      final operation =
          counter.operations().single as PNCounterIncrementOperation;

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

    test('is undone by the operations it says are the opposite', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final counter = PNCounterHandler(doc, 'counter');
      final undo = UndoManager(doc, captureTimeout: Duration.zero)
        ..track(counter);

      counter
        ..increment(3)
        ..decrement(2);
      expect(counter.value, equals(1));

      undo.undo();
      expect(counter.value, equals(3));

      undo.undo();
      expect(counter.value, equals(0));

      undo
        ..redo()
        ..redo();
      expect(counter.value, equals(1));
    });

    test('a handler that says nothing about undo has nothing to undo', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final handler = TestHandler(doc);
      final operation = TestOperation.fromHandler(handler);

      // The defaults: no inverse, and `track` refuses it rather than
      // recording steps that could never be taken back.
      expect(handler.invertible, isFalse);
      expect(handler.invert(operation), isEmpty);
      expect(handler.prepareInverse(operation), same(operation));
      expect(() => UndoManager(doc).track(handler), throwsUnsupportedError);
    });

    test('declines a change that shares its id but not its handler type', () {
      final markerDoc = CRDTDocument(peerId: PeerId.generate());
      _MarkerHandler(markerDoc, 'shared').set(42);

      // Same handler id, so the change is routed here, and the same kind
      // byte, so only the handler type tells the two apart. Being declined is
      // the right answer; reading it would be the wrong one.
      final counterDoc = CRDTDocument(peerId: PeerId.generate());
      final counter = PNCounterHandler(counterDoc, 'shared');
      counterDoc.importChanges(markerDoc.exportChanges());

      expect(counter.operations(), isEmpty);
      expect(counter.value, equals(0));
    });
  });
}

/// Holds the last value it was set to, under the same kind byte the
/// PN-counter uses for an increment.
final class _MarkerHandler extends Handler<int> {
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
  late final OperationDecoders operationDecoders = {
    setKind: (body) => _MarkerSetOperation(
          id: id,
          type: setType,
          value: UVarint.read(body, offset: 0).value,
        ),
  };

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
  _MarkerSetOperation({
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
