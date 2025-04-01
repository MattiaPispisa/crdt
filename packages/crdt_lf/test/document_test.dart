import 'package:test/test.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';

class TestHandler implements Handler {
  @override
  String get id => 'test-handler';
}

class TestOperation extends Operation {
  const TestOperation({
    required super.id,
    required super.type,
  });

  factory TestOperation.fromHandler(Handler handler) {
    return TestOperation(
      id: handler.id,
      type: OperationType.insert(handler),
    );
  }

  @override
  dynamic toPayload() => id;
}

void main() {
  group('CRDTDocument', () {
    late CRDTDocument doc;
    late Handler handler;
    late PeerId author;
    late Operation operation;

    setUp(() {
      handler = TestHandler();
      author = PeerId.generate();
      operation = TestOperation.fromHandler(handler);
      doc = CRDTDocument(peerId: author);
    });

    test('constructor creates document with generated peerId', () {
      final doc1 = CRDTDocument();
      final doc2 = CRDTDocument();
      expect(doc1.peerId, isNotNull);
      expect(doc2.peerId, isNotNull);
      expect(doc1.peerId, isNot(equals(doc2.peerId)));
    });

    test('constructor creates document with provided peerId', () {
      final doc = CRDTDocument(peerId: author);
      expect(doc.peerId, equals(author));
    });

    test('createChange creates and applies a new change', () {
      final change = doc.createChange(operation);
      expect(change.author, equals(author));
      expect(change.payload, equals(operation.toPayload()));
      expect(doc.version, equals({change.id}));
    });

    test('createChange with physical time uses provided time', () {
      final physicalTime = 1000;
      final change = doc.createChange(operation, physicalTime: physicalTime);
      expect(change.hlc.l, equals(physicalTime));
    });

    test('applyChange applies a new change', () {
      final change = Change(
        id: OperationId(author, HybridLogicalClock(l: 1, c: 1)),
        operation: operation,
        deps: {},
        hlc: HybridLogicalClock(l: 1, c: 1),
        author: author,
      );

      final applied = doc.applyChange(change);
      expect(applied, isTrue);
      expect(doc.version, equals({change.id}));
    });

    test('applyChange does not apply duplicate change', () {
      final change = Change(
        id: OperationId(author, HybridLogicalClock(l: 1, c: 1)),
        operation: operation,
        deps: {},
        hlc: HybridLogicalClock(l: 1, c: 1),
        author: author,
      );

      doc.applyChange(change);
      final applied = doc.applyChange(change);
      expect(applied, isFalse);
    });

    test('applyChange throws when change is not causally ready', () {
      final change1 = Change(
        id: OperationId(author, HybridLogicalClock(l: 1, c: 1)),
        operation: operation,
        deps: {},
        hlc: HybridLogicalClock(l: 1, c: 1),
        author: author,
      );

      final change2 = Change(
        id: OperationId(author, HybridLogicalClock(l: 1, c: 2)),
        operation: operation,
        deps: {change1.id},
        hlc: HybridLogicalClock(l: 1, c: 2),
        author: author,
      );

      expect(
        () => doc.applyChange(change2),
        throwsA(isA<StateError>()),
      );
    });

    test('exportChanges returns all changes when no version specified', () {
      final change1 = doc.createChange(operation);
      final change2 = doc.createChange(operation);

      final changes = doc.exportChanges();
      expect(changes.length, equals(2));
      expect(changes, containsAll([change1, change2]));
    });

    test('exportChanges returns changes after specified version', () {
      final change1 = doc.createChange(operation);
      final change2 = doc.createChange(operation);
      final change3 = doc.createChange(operation);

      final changes = doc.exportChanges(from: {change1.id});
      expect(changes.length, equals(2));
      expect(changes, containsAll([change2, change3]));
    });

    test('export and import work correctly', () {
      doc.createChange(operation);
      doc.createChange(operation);

      final data = doc.export();
      final newDoc = CRDTDocument();
      final imported = newDoc.import(data);

      expect(imported, equals(2));
      expect(newDoc.version, equals(doc.version));
    });

    test('importChanges applies changes in correct order', () {
      final change1 = Change(
        id: OperationId(author, HybridLogicalClock(l: 1, c: 1)),
        operation: operation,
        deps: {},
        hlc: HybridLogicalClock(l: 1, c: 1),
        author: author,
      );

      final change2 = Change(
        id: OperationId(author, HybridLogicalClock(l: 1, c: 2)),
        operation: operation,
        deps: {change1.id},
        hlc: HybridLogicalClock(l: 1, c: 2),
        author: author,
      );

      final change3 = Change(
        id: OperationId(author, HybridLogicalClock(l: 1, c: 3)),
        operation: operation,
        deps: {change2.id},
        hlc: HybridLogicalClock(l: 1, c: 3),
        author: author,
      );

      // Try to import in wrong order
      final imported = doc.importChanges([change3, change2, change1]);
      expect(imported, equals(3));
      expect(doc.version, equals({change3.id}));
    });

    test('importChanges handles cycles gracefully', () {
      final change1 = Change(
        id: OperationId(author, HybridLogicalClock(l: 1, c: 1)),
        operation: operation,
        deps: {},
        hlc: HybridLogicalClock(l: 1, c: 1),
        author: author,
      );

      final change2 = Change(
        id: OperationId(author, HybridLogicalClock(l: 1, c: 2)),
        operation: operation,
        deps: {change1.id},
        hlc: HybridLogicalClock(l: 1, c: 2),
        author: author,
      );

      // Create a cycle
      change1.deps.add(change2.id);

      expect(
        () => doc.importChanges([change1, change2]),
        throwsA(isA<StateError>()),
      );
    });

    test('toString returns correct string representation', () {
      doc.createChange(operation);
      doc.createChange(operation);

      expect(
        doc.toString(),
        equals(
            'CRDTDocument(peerId: $author, changes: 2, version: 1 frontiers)'),
      );
    });
  });
}
