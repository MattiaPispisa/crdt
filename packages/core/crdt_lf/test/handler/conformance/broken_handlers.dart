/// Handlers that break one part of the contract each.
///
/// **These tests are meant to fail.** The file has no `_test` suffix, so
/// `dart test` never picks it up on its own: `conformance_test.dart` runs it
/// in a subprocess and checks that each mutant made the clauses it breaks go
/// red. A clause that stays green here checks nothing.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';

import 'handler_conformance.dart';

void main() {
  register('remembers a value it never held', _RemembersGhost.new);
  register('forgets what it holds', _Forgets.new);
  register('folds nothing in', _FoldsNothing.new);
  register('claims an order it does not have', _ClaimsOrder.new);
  register('needs a live document', _NeedsLiveDocument.new);
  register('reports no change', _ReportsNoChange.new);
  register('cannot undo', _CannotUndo.new);
  register('snapshots what it last read', _SnapshotsLastRead.new);

  runHandlerConformanceTests(
    spec: _spec(
      'reissues spent ids',
      _ReissuesSpentIds.new,
      CRDTFugueTextHandler.spec.formats,
    ),
    read: (text) => text.value,
    edit: (text, random, token) {
      final length = text.length;
      if (length == 0 || random.nextBool()) {
        text.insert(random.nextInt(length + 1), token);
      } else {
        text.delete(random.nextInt(length), random.nextInt(3) + 1);
      }
    },
  );

  runHandlerConformanceTests(
    spec: _spec(
      'forgets pruned ids',
      _ForgetsPrunedIds.new,
      CRDTFugueMovableListHandler.spec<String>('').formats,
    ),
    read: (list) => List.of(list.value),
    edit: (list, random, token) {
      final length = list.length;
      if (length == 0 || random.nextBool()) {
        list.insert(random.nextInt(length + 1), token);
      } else {
        list.delete(random.nextInt(length), random.nextInt(3) + 1);
      }
    },
  );

  runHandlerConformanceTests(
    spec: _spec(
      'compacts away an insert',
      _DropsInsert.new,
      CRDTTextHandler.spec.formats,
    ),
    read: (text) => text.value,
    edit: (text, random, token) {
      final length = text.length;
      if (length == 0 || random.nextBool()) {
        text.insert(random.nextInt(length + 1), token);
      } else {
        text.delete(random.nextInt(length), 1);
      }
    },
  );

  runHandlerConformanceTests(
    spec: _spec(
      'snapshots without tags',
      _TaglessSet.new,
      CRDTORSetHandler.spec<String>('').formats,
    ),
    read: (set) => set.value,
    edit: (set, random, token) {
      final present = set.value.toList();
      if (present.isEmpty || random.nextBool()) {
        set.add(token);
      } else {
        set.remove(present[random.nextInt(present.length)]);
      }
    },
  );
}

/// Runs the suite against the register [build] makes, tagged [type].
void register<H extends CRDTRegisterHandler<String>>(
  String type,
  H Function(BaseCRDTDocument doc, String id, String type) build,
) {
  runHandlerConformanceTests(
    spec: _spec(type, build, CRDTRegisterHandler.spec<String>(type).formats),
    read: (register) => register.value,
    edit: (register, Random random, token) => register.set(token),
  );
}

/// The spec of the broken handler [build] makes, tagged [type], reading the
/// [formats] of the handler it breaks.
HandlerSpec<H> _spec<H extends Handler<dynamic>>(
  String type,
  H Function(BaseCRDTDocument doc, String id, String type) build,
  HandlerFormats formats,
) =>
    HandlerSpec<H>(type, (doc, id) => build(doc, id, type), formats: formats);

base class _Register extends CRDTRegisterHandler<String> {
  _Register(super.doc, super.id, String type) : super(handlerType: type);
}

/// Snapshots an empty register as one holding a value.
final class _RemembersGhost extends _Register {
  _RemembersGhost(super.doc, super.id, super.type);

  @override
  Uint8List getSnapshotState() {
    if (value != null) {
      return super.getSnapshotState();
    }
    final out = snapshotHeader()..addByte(1);
    UVarint.writeBytes(const JsonValueCodec<String>().encode('ghost'), out);
    return out.toBytes();
  }
}

/// Snapshots every register as empty.
final class _Forgets extends _Register {
  _Forgets(super.doc, super.id, super.type);

  @override
  Uint8List getSnapshotState() => (snapshotHeader()..addByte(0)).toBytes();
}

/// Keeps the cached value as it was, whatever the change.
final class _FoldsNothing extends _Register {
  _FoldsNothing(super.doc, super.id, super.type);

  @override
  String? incrementCachedState({
    required Operation operation,
    required String state,
    DeltaSink<Object?>? sink,
  }) =>
      state;
}

/// Keeps its cache when a change from the past arrives.
final class _ClaimsOrder extends _Register {
  _ClaimsOrder(super.doc, super.id, super.type);

  @override
  bool get stateIsOrderIndependent => true;
}

/// Reads only through a live document, so a history session cannot read it.
final class _NeedsLiveDocument extends _Register {
  _NeedsLiveDocument(super.doc, super.id, super.type);

  @override
  String? get value => doc is CRDTDocument ? super.value : null;
}

/// Answers every delta with the value it was given.
final class _ReportsNoChange extends _Register {
  _ReportsNoChange(super.doc, super.id, super.type);

  @override
  String? applyDelta(String? base, RegisterDelta<String> delta) => base;
}

/// Says it can undo, and undoes nothing.
final class _CannotUndo extends _Register {
  _CannotUndo(super.doc, super.id, super.type);

  @override
  List<Operation> invert(Operation operation) => const [];
}

/// Snapshots the value it held at the last read, not the one it holds now.
final class _SnapshotsLastRead extends _Register {
  _SnapshotsLastRead(super.doc, super.id, super.type);

  String? _lastRead;

  @override
  String? get value => _lastRead = super.value;

  @override
  Uint8List getSnapshotState() {
    final lastRead = _lastRead;
    if (lastRead == null) {
      return (snapshotHeader()..addByte(0)).toBytes();
    }
    final out = snapshotHeader()..addByte(1);
    UVarint.writeBytes(const JsonValueCodec<String>().encode(lastRead), out);
    return out.toBytes();
  }
}

/// Seeds its element counter from nothing, so a reload hands out the
/// counters it already spent.
final class _ReissuesSpentIds extends CRDTFugueTextHandler {
  _ReissuesSpentIds(super.doc, super.id, this._type);

  final String _type;

  @override
  String get handlerType => _type;

  @override
  Iterable<FugueElementID> knownElementIds() => const [];
}

/// Leaves the element id floor out of its snapshots, so a reload hands out
/// the counters of the elements the snapshot pruned.
final class _ForgetsPrunedIds extends CRDTFugueMovableListHandler<String> {
  _ForgetsPrunedIds(super.doc, super.id, String type)
      : super(handlerType: type);

  @override
  Map<PeerId, int> elementIdFloorForSnapshot() => const {};
}

/// Fuses two inserts into the later one, losing the earlier.
final class _DropsInsert extends CRDTTextHandler {
  _DropsInsert(super.doc, super.id, this._type);

  final String _type;

  @override
  String get handlerType => _type;

  @override
  Operation? compound(Operation accumulator, Operation current) =>
      super.compound(accumulator, current) == null ? null : current;
}

/// Writes the blob of a build before tags: every value comes back tagless.
final class _TaglessSet extends CRDTORSetHandler<String> {
  _TaglessSet(super.doc, super.id, String type) : super(handlerType: type);

  @override
  Uint8List getSnapshotState() {
    final items = value;
    final out = BytesBuilder()..addByte(1);
    UVarint.write(items.length, out);
    for (final item in items) {
      UVarint.writeBytes(const JsonValueCodec<String>().encode(item), out);
    }
    return out.toBytes();
  }
}
