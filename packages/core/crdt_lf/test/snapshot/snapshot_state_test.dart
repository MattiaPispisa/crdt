import 'dart:convert';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/snapshot/snapshot_state.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('SnapshotState', () {
    late SnapshotState state;
    late PeerId a;
    late PeerId b;

    setUp(() {
      state = SnapshotState();
      a = PeerId.generate();
      b = PeerId.generate();
    });

    HybridLogicalClock at(int counter) => HybridLogicalClock(l: 1, c: counter);

    Snapshot snapshot(
      String id,
      Map<PeerId, HybridLogicalClock> version, {
      Map<String, Uint8List> data = const {},
    }) =>
        Snapshot(id: id, versionVector: VersionVector(version), data: data);

    test('shouldApply takes a newer snapshot and refuses a divergent one', () {
      final held = snapshot('held', {a: at(1)});
      expect(state.shouldApply(held), isTrue);

      state.current = held;

      expect(state.shouldApply(snapshot('newer', {a: at(2)})), isTrue);
      // Misses peer `a`, which the held snapshot has seen.
      expect(state.shouldApply(snapshot('divergent', {b: at(2)})), isFalse);
    });

    test('merge holds the first snapshot as it is', () {
      final first = snapshot('first', {a: at(1)});

      expect(state.merge(first), same(first));
      expect(state.current, same(first));
    });

    test('merge joins two snapshots and holds the result', () {
      state.current = snapshot('mine', {a: at(1)}, data: {'x': _b('1')});

      final merged = state.merge(snapshot('theirs', {b: at(1)}));

      expect(state.current, same(merged));
      expect(merged.versionVector[a], at(1));
      expect(merged.versionVector[b], at(1));
      expect(merged.data['x'], _b('1'));
    });

    test('merge refuses concurrent states of one handler, and holds on', () {
      final held = snapshot('mine', {a: at(1)}, data: {'x': _b('1')});
      state.current = held;

      expect(
        () => state.merge(snapshot('theirs', {b: at(1)}, data: {'x': _b('2')})),
        throwsA(isA<ConcurrentSnapshotException>()),
      );
      expect(state.current, same(held));
    });

    test('versionVector adds the held snapshot to the history', () {
      final history = VersionVector({b: at(3)});
      expect(state.versionVector(history), history);

      state.current = snapshot('held', {a: at(1)});

      final version = state.versionVector(history);
      expect(version[a], at(1));
      expect(version[b], at(3));
    });

    test('prunableUpTo is what both the bound and the snapshot have seen', () {
      expect(state.prunableUpTo(VersionVector({a: at(5)})).isEmpty, isTrue);

      state.current = snapshot('held', {a: at(2), b: at(9)});

      final bound = state.prunableUpTo(VersionVector({a: at(5)}));
      expect(bound[a], at(2));
      expect(bound[b], isNull);
    });

    test('readOnlyCopy hands out a copy that cannot be written to', () {
      expect(state.readOnlyCopy(), isNull);
      state.current = snapshot('held', {a: at(1)}, data: {'x': _b('1')});

      final copy = state.readOnlyCopy()!;

      expect(copy.id, 'held');
      expect(() => copy.data['y'] = Uint8List(1), throwsUnsupportedError);
      expect(() => copy.data['x']![0] = 1, throwsUnsupportedError);
      expect(
        () => copy.versionVector.update(b, at(1)),
        throwsUnsupportedError,
      );
    });
  });
}
