import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/compound/compound.dart';
import 'package:test/test.dart';

final _peer = PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518');

void main() {
  group('Compound', () {
    late CRDTDocument doc;
    late CRDTRegisterHandler<int> plain;

    setUp(() {
      doc = CRDTDocument(peerId: _peer);
      plain = CRDTRegisterHandler<int>(doc, 'plain');
    });

    List<Operation> compact(List<Operation> operations) => Compound(
          operations: operations,
          handlers: doc.registeredHandlers,
        ).compact();

    test('folds consecutive operations of the same handler into one', () {
      final result = compact([_write(plain, 1), _write(plain, 2)]);

      expect(result, hasLength(1));
    });

    // Every operation carries the id of the change it will travel in, so the
    // survivor of a fold has one too — the later of the two, which is what
    // keeps the change sorting after everything it depends on.
    test('the survivor of a fold carries the later id', () {
      final first = _write(plain, 1);
      final second = _write(plain, 2);

      expect(first.stamp!.compareTo(second.stamp!), lessThan(0));
      expect(compact([first, second]).single.stamp, equals(second.stamp));
    });

    test('operations of different handlers are left alone', () {
      final other = CRDTRegisterHandler<int>(doc, 'other');
      final result = compact([
        _write(plain, 1),
        _write(other, 2),
        _write(plain, 3),
      ]);

      expect(result, hasLength(3));
    });

    // The rule this file exists for. A compound is one change and a change has
    // one id, but a stamped handler folded each constituent under its own. On
    // a compound touching one target the two agree; on one touching several
    // they do not, and nothing would say so until a later concurrent write
    // landed between the two ids and won on one peer while losing on the other.
    group('a stamped kind is never folded', () {
      test('a handler that tries is told, in debug', () {
        final stamped = _CompoundingStampedRegister(doc, 'bad');

        expect(
          () => compact([stamped.write(1), stamped.write(2)]),
          throwsA(isA<AssertionError>()),
        );
      });

      test('a well-behaved stamped handler keeps one change per write', () {
        final stamped = _StampedRegister(doc, 'stamped');

        doc.runInTransaction(() {
          stamped
            ..set(1)
            ..set(2)
            ..set(3);
        });

        final changes = doc.exportChanges();
        expect(changes, hasLength(3));

        // Each write kept its own id, so a peer replaying them resolves the
        // last-writer-wins race exactly as the writer did.
        final other = CRDTDocument(peerId: PeerId.generate());
        final otherStamped = _StampedRegister(other, 'stamped');
        other.importChanges(changes);

        expect(otherStamped.value, equals(3));
        expect(stamped.value, equals(3));
      });
    });
  });
}

/// Registers a write on [handler] and hands back the operation it produced.
Operation _write(CRDTRegisterHandler<int> handler, int value) {
  handler.set(value);
  return handler.operations().last;
}

/// A stamped handler that does **not** compound, which is the only shape a
/// stamped handler is allowed to have.
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
  Uint8List getSnapshotState() => Uint8List(0);
}

/// A handler written the way `Compound` refuses: stamped **and** folding.
class _CompoundingStampedRegister extends _StampedRegister {
  _CompoundingStampedRegister(super.doc, super.id);

  @override
  Operation? compound(Operation accumulator, Operation current) {
    if (accumulator is _StampedWrite && current is _StampedWrite) {
      return write(current.value);
    }
    return null;
  }
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
