import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

import 'helpers/handler.dart';

void main() {
  group('CRDTDocument', () {
    late CRDTDocument doc;
    late Handler<dynamic> handler;
    late PeerId author;
    late Operation operation;

    setUp(() {
      author = PeerId.generate();
      doc = CRDTDocument(peerId: author);
      handler = TestHandler(doc);
      operation = TestOperation.fromHandler(handler);
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

    test('document should be empty', () {
      final doc = CRDTDocument(peerId: author);
      expect(doc.isEmpty, isTrue);
    });

    test('createChange creates and applies a new change', () {
      final change = doc.createChange(operation);
      expect(change.author, equals(author));
      expect(change.payload, equals(operation.toPayload()));
      expect(doc.version, equals({change.id}));
    });

    test('clock increment on createChange', () {
      doc.createChange(operation);
      final clock1 = doc.hlc;
      doc.createChange(operation);
      final clock2 = doc.hlc;

      expect(clock1, isNot(equals(clock2)));
      expect(clock1.happenedBefore(clock2), isTrue);
    });

    test('createChange with physical time uses provided time', () {
      const physicalTime = 1000;
      final change = doc.createChange(operation, physicalTime: physicalTime);
      expect(change.hlc.l, equals(physicalTime));
    });

    test('applyChange applies a new change', () {
      final change = Change(
        id: OperationId(author, HybridLogicalClock(l: 1, c: 1)),
        operation: operation,
        deps: {},
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
        author: author,
      );

      final change2 = Change(
        id: OperationId(author, HybridLogicalClock(l: 1, c: 2)),
        operation: operation,
        deps: {change1.id},
        author: author,
      );

      expect(
        () => doc.applyChange(change2),
        throwsA(isA<CausallyNotReadyException>()),
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
      doc
        ..createChange(operation)
        ..createChange(operation);

      final data = doc.binaryExportChanges();
      final newDoc = CRDTDocument();
      final imported = newDoc.binaryImportChanges(data);

      expect(imported, equals(2));
      expect(newDoc.version, equals(doc.version));
    });

    test('importChanges applies changes in correct order', () {
      final change1 = Change(
        id: OperationId(author, HybridLogicalClock(l: 1, c: 1)),
        operation: operation,
        deps: {},
        author: author,
      );

      final change2 = Change(
        id: OperationId(author, HybridLogicalClock(l: 1, c: 2)),
        operation: operation,
        deps: {change1.id},
        author: author,
      );

      final change3 = Change(
        id: OperationId(author, HybridLogicalClock(l: 1, c: 3)),
        operation: operation,
        deps: {change2.id},
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
        author: author,
      );

      final change2 = Change(
        id: OperationId(author, HybridLogicalClock(l: 1, c: 2)),
        operation: operation,
        deps: {change1.id},
        author: author,
      );

      // Create a cycle
      change1.deps.add(change2.id);

      expect(
        () => doc.importChanges([change1, change2]),
        throwsA(isA<ChangesCycleException>()),
      );
    });

    test('localChanges stream emits change on createChange', () async {
      // Expect one change to be emitted
      final expectation = expectLater(
        doc.localChanges,
        emits(isA<Change>()),
      );

      // Create a change
      doc.createChange(operation);

      // Wait for the stream to emit
      await expectation;

      // Optional: Further verification of the emitted change
      doc.localChanges.listen(
        expectAsync1(
          (emittedChange) {
            expect(emittedChange.author, equals(author));
          },
        ),
      ); // Ensure the listener is called exactly once

      // Create another change to trigger the listener above
      doc.createChange(operation);
    });

    test('localChanges stream is closed on dispose', () async {
      // Expect the stream to be done (closed)
      final expectation = expectLater(
        doc.localChanges,
        emitsDone,
      );

      // Dispose the document
      doc.dispose();

      // Wait for the stream to close
      await expectation;
    });

    test('import should not accept changes already in version vector', () {
      final change1 = Change(
        id: OperationId(author, HybridLogicalClock(l: 1, c: 1)),
        operation: operation,
        deps: {},
        author: author,
      );

      final change2 = Change(
        id: OperationId(author, HybridLogicalClock(l: 1, c: 3)),
        operation: operation,
        deps: {},
        author: author,
      );

      final snapshot = Snapshot(
        id: 'id',
        versionVector: VersionVector({author: change2.hlc}),
        data: {},
      );

      final imported = doc.importSnapshot(snapshot);
      final applied = doc.importChanges([change1, change2]);

      expect(imported, isTrue);
      expect(applied, equals(0));
      expect(doc.version, isEmpty);
      expect(doc.exportChanges(), isEmpty);
    });

    test('import accept old changes not in snapshot', () {
      final author1 = PeerId.generate();
      final author2 = PeerId.generate();

      final change1 = Change(
        id: OperationId(author1, HybridLogicalClock(l: 1, c: 1)),
        operation: operation,
        deps: {},
        author: author1,
      );

      final change2 = Change(
        id: OperationId(author2, HybridLogicalClock(l: 1, c: 1)),
        operation: operation,
        deps: {},
        author: author2,
      );

      final change3 = Change(
        id: OperationId(author1, HybridLogicalClock(l: 1, c: 3)),
        operation: operation,
        deps: {},
        author: author1,
      );

      final snapshot = Snapshot(
        id: 'id',
        versionVector: VersionVector({author1: change3.hlc}),
        data: {},
      );

      expect(doc.shouldApplySnapshot(snapshot), isTrue);

      final imported = doc.importSnapshot(snapshot);
      final applied = doc.importChanges([change1, change2, change3]);

      expect(imported, isTrue);
      expect(applied, equals(1));
      expect(doc.version, equals({change2.id}));
      expect(doc.exportChanges(), containsAll([change2]));
    });

    test('should not accept snapshot if divergent', () {
      final author1 = PeerId.generate();
      final author2 = PeerId.generate();

      doc.importSnapshot(
        Snapshot(
          id: 'id',
          versionVector: VersionVector({
            author1: HybridLogicalClock(l: 1, c: 1),
          }),
          data: {},
        ),
      );

      final snapshot = Snapshot(
        id: 'id2',
        versionVector: VersionVector({
          author2: HybridLogicalClock(l: 1, c: 2),
        }),
        data: {},
      );

      // author2 is not in the version vector
      expect(doc.shouldApplySnapshot(snapshot), isFalse);
    });

    test('toString returns correct string representation', () {
      doc
        ..createChange(operation)
        ..createChange(operation);

      expect(
        doc.toString(),
        equals(
          'CRDTDocument(peerId: $author, changes: 2, version: 1 frontiers)',
        ),
      );
    });

    group('documents consistency', () {
      late CRDTDocument serverDoc;
      late CRDTDocument clientDoc;
      late CRDTListHandler<String> serverHandler;
      late CRDTListHandler<String> clientHandler;

      setUp(() {
        serverDoc = CRDTDocument();
        clientDoc = CRDTDocument();
        serverHandler = CRDTListHandler<String>(serverDoc, 'todo_list');
        clientHandler = CRDTListHandler<String>(clientDoc, 'todo_list');
      });

      test('should be consistent', () {
        clientHandler.insert(0, 'Hello');

        serverDoc.importChanges(clientDoc.exportChanges());

        expect(serverHandler.value, clientHandler.value);

        clientHandler.insert(1, 'World');

        // server is behind client, server doesn't have client version
        expect(
          () => serverDoc.exportChanges(from: clientDoc.version),
          throwsA(isA<Error>()),
        );

        // client do nothing, client is ahead of server
        clientDoc.importChanges(serverDoc.exportChanges());
        expect(serverHandler.value, ['Hello']);
        expect(clientHandler.value, ['Hello', 'World']);

        // server import client changes, server is up to date
        serverDoc.importChanges(clientDoc.exportChanges());
        expect(serverHandler.value, ['Hello', 'World']);
        expect(serverHandler.value, clientHandler.value);
      });

      test('should be consistent', () {
        clientHandler.insert(0, 'Hello');
        serverDoc.importChanges(clientDoc.exportChanges());

        clientHandler.insert(1, 'World');
        final serverSnapshot = serverDoc.takeSnapshot();

        clientDoc.importChanges(serverDoc.exportChanges());
        final snapshotImported = clientDoc.importSnapshot(serverSnapshot);

        expect(snapshotImported, isFalse);
        expect(serverHandler.value, ['Hello']);
        expect(clientHandler.value, ['Hello', 'World']);
        expect(clientDoc.exportChanges().length, 2);

        clientDoc.mergeSnapshot(serverSnapshot);
        expect(clientDoc.exportChanges().length, 1);

        // server import client changes, server is up to date
        final changesImportedCount =
            serverDoc.importChanges(clientDoc.exportChanges());
        expect(changesImportedCount, 1);

        expect(serverHandler.value, ['Hello', 'World']);
        expect(serverHandler.value, clientHandler.value);
      });

      test('should be consistent', () {
        clientHandler.insert(0, 'Hello');
        serverDoc.importChanges(clientDoc.exportChanges());

        clientHandler.insert(1, 'World');
        final serverSnapshot = serverDoc.takeSnapshot();

        expect(
          clientDoc.import(
            snapshot: serverSnapshot,
            changes: serverDoc.exportChanges(),
          ),
          equals(-1),
        );

        expect(
          clientDoc.import(
            snapshot: serverSnapshot,
            changes: serverDoc.exportChanges(),
            merge: true,
          ),
          equals(0),
        );

        expect(clientDoc.exportChanges().length, 1);
        final changesImportedCount =
            serverDoc.importChanges(clientDoc.exportChanges());
        expect(changesImportedCount, 1);

        expect(serverHandler.value, ['Hello', 'World']);
        expect(serverHandler.value, clientHandler.value);
      });

      test('should be consistent', () {
        clientHandler.insert(0, 'Hello');
        serverDoc.importChanges(clientDoc.exportChanges());

        clientHandler.insert(1, 'World');
        serverHandler.insert(1, 'All');

        expect(
          () => serverDoc.exportChanges(from: clientDoc.version),
          throwsA(isA<Error>()),
        );
        expect(
          () => clientDoc.exportChanges(from: serverDoc.version),
          throwsA(isA<Error>()),
        );

        expect(
          clientDoc.import(changes: serverDoc.exportChanges()),
          equals(1),
        );

        expect(
          serverDoc.import(changes: clientDoc.exportChanges()),
          equals(1),
        );

        expect(serverHandler.value, unorderedEquals(['Hello', 'World', 'All']));
        expect(serverHandler.value, clientHandler.value);
      });
    });
  });
}
