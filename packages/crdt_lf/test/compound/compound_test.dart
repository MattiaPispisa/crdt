import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/compound/compound.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

final _peer = PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518');

OperationStamp _stamp(int c) =>
    OperationStamp(hlc: HybridLogicalClock(l: 1, c: c), peerId: _peer);

void main() {
  group('Compound', () {
    late CRDTDocument doc;
    late _StampedRegister stamped;
    late CRDTRegisterHandler<int> plain;

    setUp(() {
      doc = CRDTDocument(peerId: _peer);
      stamped = _StampedRegister(doc, 'stamped');
      plain = CRDTRegisterHandler<int>(doc, 'plain');
    });

    List<Operation> compact(List<Operation> operations) => Compound(
          operations: operations,
          handlers: doc.registeredHandlers,
        ).compact();

    test('folds consecutive operations of the same handler into one', () {
      final result = compact([
        stamped.write(1)..stamp = _stamp(1),
        stamped.write(2)..stamp = _stamp(2),
        stamped.write(3)..stamp = _stamp(3),
      ]);

      expect(result, hasLength(1));
      expect((result.single as _StampedWrite).value, equals(3));
    });

    test('the folded operation carries the greatest stamp', () {
      final result = compact([
        stamped.write(1)..stamp = _stamp(1),
        stamped.write(2)..stamp = _stamp(2),
        stamped.write(3)..stamp = _stamp(3),
      ]);

      expect(result.single.stamp, equals(_stamp(3)));
    });

    test('and takes it whatever order the operations came in', () {
      // Registration always stamps in increasing order, so this is the rule
      // stated as a rule rather than as a side effect of that.
      final result = compact([
        stamped.write(1)..stamp = _stamp(3),
        stamped.write(2)..stamp = _stamp(1),
        stamped.write(3)..stamp = _stamp(2),
      ]);

      expect(result.single.stamp, equals(_stamp(3)));
    });

    test('a handler that is not stamped folds into an unstamped operation', () {
      final result = compact([
        _write(plain, 1),
        _write(plain, 2),
      ]);

      expect(result, hasLength(1));
      expect(result.single.stamp, isNull);
    });

    test('operations of different handlers are left alone', () {
      final result = compact([
        stamped.write(1)..stamp = _stamp(1),
        _write(plain, 2),
        stamped.write(3)..stamp = _stamp(3),
      ]);

      expect(result, hasLength(3));
      expect(result.first.stamp, equals(_stamp(1)));
      expect(result.last.stamp, equals(_stamp(3)));
    });

    test('a transaction produces one change that a second peer reads', () {
      doc.runInTransaction(() {
        stamped
          ..set(1)
          ..set(2)
          ..set(3);
      });

      final changes = doc.exportChanges();
      expect(changes, hasLength(1));

      final other = CRDTDocument(peerId: PeerId.generate());
      final otherStamped = _StampedRegister(other, 'stamped');
      other.importChanges(changes);

      expect(otherStamped.value, equals(3));
      expect(stamped.value, equals(3));
    });
  });
}

/// Builds a register write without going through the document.
Operation _write(CRDTRegisterHandler<int> handler, int value) {
  handler.set(value);
  return handler.operations().last;
}

/// A stamped handler whose consecutive writes fold into one.
///
/// Nothing in `lib/` is both stamped and compounding today, so the rule that a
/// folded operation carries the greater stamp has nothing to run on without a
/// handler like this one.
class _StampedRegister extends Handler<int> {
  _StampedRegister(super.doc, this._id);

  final String _id;

  @override
  String get id => _id;

  @override
  late final OperationFactory operationFactory = _fromBytes;

  Operation _fromBytes(OperationEnvelope env, Uint8List body) => _StampedWrite(
        id: id,
        type: writeType,
        value: UVarint.read(body, offset: 0).value,
      );

  late final OperationType writeType = OperationType.custom(
    this,
    kind: 4,
    name: 'write',
    stamped: true,
  );

  _StampedWrite write(int value) =>
      _StampedWrite(id: id, type: writeType, value: value);

  void set(int value) => doc.registerOperation(write(value));

  int get value {
    var current = 0;
    for (final operation in operations()) {
      if (operation is _StampedWrite) {
        current = operation.value;
      }
    }
    return current;
  }

  @override
  Operation? compound(Operation accumulator, Operation current) {
    if (accumulator is _StampedWrite && current is _StampedWrite) {
      // A fresh operation, so the stamp Compound puts on it is visibly its
      // own rather than one of the inputs' left in place.
      return write(current.value);
    }
    return null;
  }

  @override
  Uint8List getSnapshotState() => Uint8List(0);
}

class _StampedWrite extends Operation {
  _StampedWrite({
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
