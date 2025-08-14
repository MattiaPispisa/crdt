import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

import '../helpers/handler.dart';
import '../helpers/matcher.dart';

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
        data: {'test': 'Hello World!'},
      );

      expect(snapshot.id, equals('id'));
      expect(
        snapshot.versionVector.entries.length,
        equals(1),
      );
      expect(snapshot.versionVector.entries.first.key, equals(author));
      expect(
        snapshot.versionVector.entries.first.value,
        equals(HybridLogicalClock(l: 1, c: 1)),
      );
      expect(snapshot.data, equals({'test': 'Hello World!'}));
    });

    test('should be immutable', () {
      final snapshot = Snapshot(
        id: 'id',
        versionVector: VersionVector({author: HybridLogicalClock(l: 1, c: 1)}),
        data: {'test': 'Hello World!'},
      );

      expect(
        () => snapshot.data['test'] = 'Hello World!',
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
        data: {'test': 'Hello World!'},
      );

      expect(snapshot.id, isString);
      expect(
        snapshot.versionVector.entries.length,
        equals(1),
      );
      expect(snapshot.versionVector.entries.first.key, equals(author));
      expect(
        snapshot.versionVector.entries.first.value,
        equals(HybridLogicalClock(l: 1, c: 2)),
      );
      expect(snapshot.data, equals({'test': 'Hello World!'}));
    });

    test('should toJson correctly', () {
      final snapshot = Snapshot(
        id: 'id',
        versionVector: VersionVector({author: HybridLogicalClock(l: 1, c: 1)}),
        data: {'test': 'Hello World!'},
      );

      final json = snapshot.toJson();
      expect(json, isMap);
      expect(json['id'], equals('id'));
      expect(
        json['versionVector'],
        equals({
          'vector': {author.toString(): 65537},
        }),
      );
      expect(json['data'], equals({'test': 'Hello World!'}));
    });

    test('should fromJson correctly', () {
      final json = Snapshot(
        id: 'id',
        versionVector: VersionVector({author: HybridLogicalClock(l: 1, c: 1)}),
        data: {'test': 'Hello World!'},
      ).toJson();

      final snapshot = Snapshot.fromJson(json);
      expect(snapshot.id, equals('id'));
      expect(
        snapshot.versionVector.entries.length,
        equals(1),
      );
      expect(snapshot.versionVector.entries.first.key, equals(author));
      expect(
        snapshot.versionVector.entries.first.value,
        equals(HybridLogicalClock(l: 1, c: 1)),
      );
      expect(snapshot.data, equals({'test': 'Hello World!'}));
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
          'todo-list': ['apple', 'banana'],
          'test': 'Hello',
        },
      );

      final newerSnapshot = Snapshot(
        id: 'id2',
        versionVector: VersionVector({
          author1: HybridLogicalClock(l: 1, c: 1),
          author2: HybridLogicalClock(l: 1, c: 2),
        }),
        data: {
          'test': 'Hello World!',
          'document': 'Thesis: CRDTs are cool',
        },
      );

      final merged = snapshot.merged(newerSnapshot);

      expect(merged.data, containsPair('test', 'Hello World!'));
      expect(merged.data, containsPair('todo-list', ['apple', 'banana']));
      expect(merged.data, containsPair('document', 'Thesis: CRDTs are cool'));

      expect(
        merged.versionVector.entries.length,
        equals(2),
      );
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
        data: {'test': 'Hello'},
      );

      final newerSnapshot = Snapshot(
        id: 'id2',
        versionVector: VersionVector({author2: HybridLogicalClock(l: 1, c: 2)}),
        data: {'test': 'Hello World!'},
      );

      final merged = snapshot.merged(newerSnapshot);

      expect(merged.data, containsPair('test', 'Hello'));
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
          'common_key': 'value from base',
          'base_only_key': 'base only',
        },
      );

      final snapshotOther = Snapshot(
        id: 'other_id',
        versionVector: VersionVector({
          author1: HybridLogicalClock(l: 1, c: 1),
          author2: HybridLogicalClock(l: 2, c: 1),
        }),
        data: {
          'common_key': 'value from other', // This should overwrite base
          'other_only_key': 'other only',
        },
      );

      // Merge other into base
      final merged = snapshotBase.merged(snapshotOther);

      // Verify data merge preference
      expect(merged.data, containsPair('common_key', 'value from other'));
      expect(merged.data, containsPair('base_only_key', 'base only'));
      expect(merged.data, containsPair('other_only_key', 'other only'));
      expect(merged.data.length, 3);

      // Verify version vector merge (should contain both authors)
      expect(
        merged.versionVector.entries.length, // Check number of entries
        equals(2),
      );

      // Find entries by key
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
  });
}
