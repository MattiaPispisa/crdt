// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

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

    test('a deletions registry it cannot read refuses a concurrent merge', () {
      const registry = 'crdt_lf/deleted-handlers';
      state.current = snapshot(
        'held',
        {a: at(1)},
        data: {
          registry: Uint8List.fromList([1, 1, 3, ..._b('"x"')]),
        },
      );
      final incoming = snapshot(
        'incoming',
        {b: at(1)},
        data: {
          registry: Uint8List.fromList([2, 0]),
        },
      );

      expect(
        () => state.merge(incoming),
        throwsA(isA<ConcurrentSnapshotException>()),
      );
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
