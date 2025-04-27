import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

import '../helpers/handler.dart';
import '../helpers/string.dart';

void main() {
  group('Snapshot', () {
    late Operation operation;
    late Handler handler;
    late PeerId author;

    setUp(() {
      author = PeerId.generate();
      handler = TestHandler(CRDTDocument(peerId: author));
      operation = TestOperation.fromHandler(handler);
    });

    test('should create correctly', () {
      final snapshot = Snapshot(
        id: 'id',
        versionVector: VersionVector({author: HybridLogicalClock(l: 1, c: 1)}),
        data: {'test': "Hello World!"},
      );

      expect(snapshot.id, equals('id'));
      expect(
        snapshot.versionVector.vector,
        equals({author: HybridLogicalClock(l: 1, c: 1)}),
      );
      expect(snapshot.data, equals({'test': "Hello World!"}));
    });

    test('should be immutable', () {
      final snapshot = Snapshot(
        id: 'id',
        versionVector: VersionVector({author: HybridLogicalClock(l: 1, c: 1)}),
        data: {'test': "Hello World!"},
      );

      expect(
        () => snapshot.versionVector.vector[author] =
            HybridLogicalClock(l: 1, c: 3),
        throwsA(isA<UnsupportedError>()),
      );
      expect(
        () => snapshot.data['test'] = 'Hello World!',
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('should create from document version correctly', () {
      final doc = CRDTDocument(peerId: author);

      doc.importChanges([
        Change(
          id: OperationId(author, HybridLogicalClock(l: 1, c: 1)),
          operation: operation,
          deps: {},
          author: author,
          hlc: HybridLogicalClock(l: 1, c: 1),
        ),
        Change(
          id: OperationId(author, HybridLogicalClock(l: 1, c: 2)),
          operation: operation,
          deps: {},
          author: author,
          hlc: HybridLogicalClock(l: 1, c: 2),
        ),
      ]);

      final snapshot = Snapshot.create(
        version: doc.version,
        data: {'test': "Hello World!"},
      );

      expect(snapshot.id, isString);
      expect(
        snapshot.versionVector.vector,
        equals({author: HybridLogicalClock(l: 1, c: 2)}),
      );
      expect(snapshot.data, equals({'test': "Hello World!"}));
    });

    test('should toJson correctly', () {
      final snapshot = Snapshot(
        id: 'id',
        versionVector: VersionVector({author: HybridLogicalClock(l: 1, c: 1)}),
        data: {'test': "Hello World!"},
      );

      final json = snapshot.toJson();
      expect(json, isMap);
      expect(json['id'], equals('id'));
      expect(
        json['versionVector'],
        equals({
          'vector': {author.toString(): 65537}
        }),
      );
      expect(json['data'], equals({'test': "Hello World!"}));
    });

    test('should fromJson correctly', () {
      final json = Snapshot(
        id: 'id',
        versionVector: VersionVector({author: HybridLogicalClock(l: 1, c: 1)}),
        data: {'test': "Hello World!"},
      ).toJson();

      final snapshot = Snapshot.fromJson(json);
      expect(snapshot.id, equals('id'));
      expect(
        snapshot.versionVector.vector,
        equals({author: HybridLogicalClock(l: 1, c: 1)}),
      );
      expect(snapshot.data, equals({'test': "Hello World!"}));
    });

    test('same version should produce same id', () {
      final doc = CRDTDocument(peerId: author);

      doc.importChanges([
        Change(
          id: OperationId(author, HybridLogicalClock(l: 1, c: 1)),
          operation: operation,
          deps: {},
          author: author,
          hlc: HybridLogicalClock(l: 1, c: 1),
        ),
        Change(
          id: OperationId(author, HybridLogicalClock(l: 1, c: 2)),
          operation: operation,
          deps: {},
          author: author,
          hlc: HybridLogicalClock(l: 1, c: 2),
        ),
      ]);

      final doc2 = CRDTDocument(peerId: PeerId.generate());
      doc2.importChanges([
        Change(
          id: OperationId(author, HybridLogicalClock(l: 1, c: 1)),
          operation: operation,
          deps: {},
          author: author,
          hlc: HybridLogicalClock(l: 1, c: 1),
        ),
        Change(
          id: OperationId(author, HybridLogicalClock(l: 1, c: 2)),
          operation: operation,
          deps: {},
          author: author,
          hlc: HybridLogicalClock(l: 1, c: 2),
        ),
      ]);

      final snapshot = Snapshot.create(
        version: doc.version,
        data: {},
      );

      final snapshot2 = Snapshot.create(
        version: doc2.version,
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
          'todo-list': ["apple", "banana"],
          'test': "Hello",
        },
      );

      final snapshot2 = Snapshot(
        id: 'id2',
        versionVector: VersionVector({author2: HybridLogicalClock(l: 1, c: 2)}),
        data: {
          'test': "Hello World!",
          "document": "Thesis: CRDTs are cool",
        },
      );

      final merged = snapshot.merged(snapshot2);

      expect(merged.data, containsPair('test', 'Hello World!'));
      expect(merged.data, containsPair('todo-list', ["apple", "banana"]));
      expect(merged.data, containsPair("document", "Thesis: CRDTs are cool"));

      expect(
        merged.versionVector.vector,
        equals({
          author1: HybridLogicalClock(l: 1, c: 1),
          author2: HybridLogicalClock(l: 1, c: 2)
        }),
      );
    });
  });

  group('VersionVector', () {
    test('should compare correctly', () {
      final author = PeerId.generate();
      final versionVector =
          VersionVector({author: HybridLogicalClock(l: 1, c: 1)});
      final versionVector2 =
          VersionVector({author: HybridLogicalClock(l: 1, c: 2)});

      expect(versionVector.isNewerThan(versionVector2), isFalse);
      expect(versionVector2.isNewerThan(versionVector), isTrue);
    });

    test('should compare correctly with multiple peers', () {
      final author = PeerId.generate();
      final author2 = PeerId.generate();

      final versionVector = VersionVector({
        author: HybridLogicalClock(l: 1, c: 1),
        author2: HybridLogicalClock(l: 1, c: 3),
      });

      final versionVector2 = VersionVector({
        author: HybridLogicalClock(l: 1, c: 1),
        author2: HybridLogicalClock(l: 1, c: 2),
      });

      expect(versionVector.isNewerThan(versionVector2), isTrue);
      expect(versionVector2.isNewerThan(versionVector), isFalse);
    });

    test('should compare correctly with empty version vector', () {
      final versionVector = VersionVector({});
      final versionVector2 = VersionVector({});

      expect(versionVector.isNewerThan(versionVector2), isFalse);
      expect(versionVector2.isNewerThan(versionVector), isFalse);
    });

    test('should compare correctly with strict comparison', () {
      final author = PeerId.generate();
      final author2 = PeerId.generate();

      final versionVector = VersionVector({
        author: HybridLogicalClock(l: 1, c: 1),
        author2: HybridLogicalClock(l: 1, c: 3),
      });

      final versionVector2 = VersionVector({
        author: HybridLogicalClock(l: 1, c: 1),
        author2: HybridLogicalClock(l: 1, c: 2),
      });

      expect(versionVector.isStrictlyNewerThan(versionVector2), isFalse);
      expect(versionVector2.isStrictlyNewerThan(versionVector), isFalse);
    });

    test('should compare correctly with different peers', () {
      final author = PeerId.generate();
      final author2 = PeerId.generate();

      final versionVector = VersionVector({
        author: HybridLogicalClock(l: 1, c: 1),
      });

      final versionVector2 = VersionVector({
        author2: HybridLogicalClock(l: 1, c: 1),
      });

      expect(versionVector.isStrictlyNewerThan(versionVector2), isTrue);
      expect(versionVector2.isStrictlyNewerThan(versionVector), isTrue);
    });

    test('should merge correctly', () {
      final author = PeerId.generate();
      final author2 = PeerId.generate();

      final versionVector =
          VersionVector({author: HybridLogicalClock(l: 1, c: 1)});
      final versionVector2 =
          VersionVector({author2: HybridLogicalClock(l: 1, c: 1)});

      final merged = versionVector.merged(versionVector2);
      expect(
          merged.vector,
          equals({
            author: HybridLogicalClock(l: 1, c: 1),
            author2: HybridLogicalClock(l: 1, c: 1)
          }));
    });

    test('should merge correctly with multiple peers', () {
      final author = PeerId.generate();
      final author2 = PeerId.generate();
      final author3 = PeerId.generate();

      final versionVector = VersionVector({
        author: HybridLogicalClock(l: 1, c: 1),
        author2: HybridLogicalClock(l: 1, c: 4),
        author3: HybridLogicalClock(l: 1, c: 3),
      });

      final versionVector2 = VersionVector({
        author: HybridLogicalClock(l: 1, c: 2),
        author2: HybridLogicalClock(l: 1, c: 2),
        author3: HybridLogicalClock(l: 1, c: 7),
      });

      final merged = versionVector.merged(versionVector2);
      expect(
        merged.vector,
        equals({
          author: HybridLogicalClock(l: 1, c: 2),
          author2: HybridLogicalClock(l: 1, c: 4),
          author3: HybridLogicalClock(l: 1, c: 7),
        }),
      );
    });
  });
}
