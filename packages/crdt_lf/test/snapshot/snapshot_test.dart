import 'dart:convert';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

import '../helpers/handler.dart';
import '../helpers/matcher.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('Snapshot', () {
    late Operation operation;
    late Handler<dynamic> handler;
    late PeerId author;

    setUp(() {
      author = PeerId.generate();
      handler = TestHandler(CRDTDocument(peerId: author));
      operation = TestOperation.fromHandler(handler);
    });

    test('should create empty snapshot', () {
      final snapshot = Snapshot.create(
        versionVector: VersionVector({}),
        data: {},
      );

      expect(snapshot.id, isString);
      expect(snapshot.versionVector.isEmpty, isTrue);
      expect(snapshot.data.isEmpty, isTrue);
    });

    test('should create correctly', () {
      final snapshot = Snapshot(
        id: 'id',
        versionVector: VersionVector({author: HybridLogicalClock(l: 1, c: 1)}),
        data: {'test': _b('Hello World!')},
      );

      expect(snapshot.id, equals('id'));
      expect(snapshot.versionVector.entries.length, equals(1));
      expect(snapshot.versionVector.entries.first.key, equals(author));
      expect(
        snapshot.versionVector.entries.first.value,
        equals(HybridLogicalClock(l: 1, c: 1)),
      );
      expect(snapshot.data, equals({'test': _b('Hello World!')}));
    });

    test('should be immutable', () {
      final snapshot = Snapshot(
        id: 'id',
        versionVector: VersionVector({author: HybridLogicalClock(l: 1, c: 1)}),
        data: {'test': _b('Hello World!')},
      );

      expect(
        () => snapshot.data['test'] = _b('Hello World!'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('should create from document version correctly', () {
      final doc = CRDTDocument(peerId: author)
        ..importChanges([
          Change(
            id: OperationId(author, HybridLogicalClock(l: 1, c: 1)),
            operation: operation,
            deps: {},
            author: author,
          ),
          Change(
            id: OperationId(author, HybridLogicalClock(l: 1, c: 2)),
            operation: operation,
            deps: {},
            author: author,
          ),
        ]);

      final snapshot = Snapshot.create(
        versionVector: doc.getVersionVector(),
        data: {'test': _b('Hello World!')},
      );

      expect(snapshot.id, isString);
      expect(snapshot.versionVector.entries.length, equals(1));
      expect(snapshot.versionVector.entries.first.key, equals(author));
      expect(
        snapshot.versionVector.entries.first.value,
        equals(HybridLogicalClock(l: 1, c: 2)),
      );
      expect(snapshot.data, equals({'test': _b('Hello World!')}));
    });

    test('toString contains id, versionVector and entry count', () {
      final snapshot = Snapshot(
        id: 'id',
        versionVector: VersionVector({author: HybridLogicalClock(l: 1, c: 1)}),
        data: {'test': _b('Hello World!')},
      );

      expect(snapshot.toString(), contains('Snapshot(id: id'));
      expect(
        snapshot.toString(),
        contains('versionVector: VersionVector(vector: '),
      );
      expect(snapshot.toString(), contains('data: 1 entries'));
    });

    test('same version should produce same id', () {
      final doc = CRDTDocument(peerId: author)
        ..importChanges([
          Change(
            id: OperationId(author, HybridLogicalClock(l: 1, c: 1)),
            operation: operation,
            deps: {},
            author: author,
          ),
          Change(
            id: OperationId(author, HybridLogicalClock(l: 1, c: 2)),
            operation: operation,
            deps: {},
            author: author,
          ),
        ]);

      final doc2 = CRDTDocument(peerId: PeerId.generate())
        ..importChanges([
          Change(
            id: OperationId(author, HybridLogicalClock(l: 1, c: 1)),
            operation: operation,
            deps: {},
            author: author,
          ),
          Change(
            id: OperationId(author, HybridLogicalClock(l: 1, c: 2)),
            operation: operation,
            deps: {},
            author: author,
          ),
        ]);

      final snapshot = Snapshot.create(
        versionVector: doc.getVersionVector(),
        data: {},
      );

      final snapshot2 = Snapshot.create(
        versionVector: doc2.getVersionVector(),
        data: {},
      );

      expect(snapshot.id, equals(snapshot2.id));
    });

    test('should merge correctly and preserve data from newer snapshot', () {
      final author1 = PeerId.generate();
      final author2 = PeerId.generate();

      final snapshot = Snapshot(
        id: 'id1',
        versionVector: VersionVector({author1: HybridLogicalClock(l: 1, c: 1)}),
        data: {
          'todo-list': _b('apple,banana'),
          'test': _b('Hello'),
        },
      );

      final newerSnapshot = Snapshot(
        id: 'id2',
        versionVector: VersionVector({
          author1: HybridLogicalClock(l: 1, c: 1),
          author2: HybridLogicalClock(l: 1, c: 2),
        }),
        data: {
          'test': _b('Hello World!'),
          'document': _b('Thesis: CRDTs are cool'),
        },
      );

      final merged = snapshot.merged(newerSnapshot);

      expect(merged.data['test'], equals(_b('Hello World!')));
      expect(merged.data['todo-list'], equals(_b('apple,banana')));
      expect(merged.data['document'], equals(_b('Thesis: CRDTs are cool')));

      expect(merged.versionVector.entries.length, equals(2));
      expect(merged.versionVector.entries.first.key, equals(author1));
      expect(
        merged.versionVector.entries.first.value,
        equals(HybridLogicalClock(l: 1, c: 1)),
      );
      expect(merged.versionVector.entries.last.key, equals(author2));
      expect(
        merged.versionVector.entries.last.value,
        equals(HybridLogicalClock(l: 1, c: 2)),
      );
    });

    test('should prefer data if other is not strictly newer', () {
      final author1 = PeerId.generate();
      final author2 = PeerId.generate();

      final snapshot = Snapshot(
        id: 'id1',
        versionVector: VersionVector({author1: HybridLogicalClock(l: 1, c: 1)}),
        data: {'test': _b('Hello')},
      );

      final newerSnapshot = Snapshot(
        id: 'id2',
        versionVector: VersionVector({author2: HybridLogicalClock(l: 1, c: 2)}),
        data: {'test': _b('Hello World!')},
      );

      final merged = snapshot.merged(newerSnapshot);

      expect(merged.data['test'], equals(_b('Hello')));
    });

    test(
        'merged should prefer data from the other snapshot'
        ' when version vector is newer', () {
      final author1 = PeerId.generate();
      final author2 = PeerId.generate();

      final snapshotBase = Snapshot(
        id: 'base_id',
        versionVector: VersionVector({author1: HybridLogicalClock(l: 1, c: 1)}),
        data: {
          'common_key': _b('value from base'),
          'base_only_key': _b('base only'),
        },
      );

      final snapshotOther = Snapshot(
        id: 'other_id',
        versionVector: VersionVector({
          author1: HybridLogicalClock(l: 1, c: 1),
          author2: HybridLogicalClock(l: 2, c: 1),
        }),
        data: {
          'common_key': _b('value from other'),
          'other_only_key': _b('other only'),
        },
      );

      final merged = snapshotBase.merged(snapshotOther);

      expect(merged.data['common_key'], equals(_b('value from other')));
      expect(merged.data['base_only_key'], equals(_b('base only')));
      expect(merged.data['other_only_key'], equals(_b('other only')));
      expect(merged.data.length, 3);

      expect(merged.versionVector.entries.length, equals(2));

      final entry1 = merged.versionVector.entries.firstWhere(
        (entry) => entry.key == author1,
        orElse: () => throw StateError('Author1 not found in merged VV'),
      );
      final entry2 = merged.versionVector.entries.firstWhere(
        (entry) => entry.key == author2,
        orElse: () => throw StateError('Author2 not found in merged VV'),
      );

      expect(entry1.value, equals(HybridLogicalClock(l: 1, c: 1)));
      expect(entry2.value, equals(HybridLogicalClock(l: 2, c: 1)));
    });

    test('toBytes/fromBytes round-trips id, versionVector and data', () {
      final p = PeerId.generate();
      final snapshot = Snapshot(
        id: 'snap-id',
        versionVector: VersionVector({p: HybridLogicalClock(l: 5, c: 1)}),
        data: {
          'a': _b('one'),
          'b': _b('hello'),
          'c': Uint8List.fromList([1, 2]),
        },
      );

      final decoded = Snapshot.fromBytes(snapshot.toBytes());
      expect(decoded.id, equals(snapshot.id));
      expect(decoded.versionVector[p], equals(snapshot.versionVector[p]));
      expect(decoded.data.keys.toSet(), equals(snapshot.data.keys.toSet()));
      for (final key in snapshot.data.keys) {
        expect(decoded.data[key], equals(snapshot.data[key]));
      }
    });

    test('toBytes/fromBytes round-trips an empty snapshot', () {
      final snapshot = Snapshot(
        id: 'empty',
        versionVector: VersionVector({}),
        data: const <String, Uint8List>{},
      );
      final decoded = Snapshot.fromBytes(snapshot.toBytes());
      expect(decoded.id, equals(snapshot.id));
      expect(decoded.versionVector.isEmpty, isTrue);
      expect(decoded.data, isEmpty);
    });
  });
}
