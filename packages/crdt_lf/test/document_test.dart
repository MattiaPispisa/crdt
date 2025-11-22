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

    test('constructor creates document with generated peerId and id', () {
      final doc1 = CRDTDocument();
      final doc2 = CRDTDocument();

      expect(doc1.peerId, isNotNull);
      expect(doc2.peerId, isNotNull);

      expect(doc1.documentId, isNotNull);
      expect(doc2.documentId, isNotNull);

      expect(doc1.peerId, isNot(equals(doc2.peerId)));
      expect(doc1.documentId, isNot(equals(doc2.documentId)));
    });

    test(
        'constructor creates document with'
        ' provided peerId and id', () {
      final doc = CRDTDocument(peerId: author, documentId: 'docId');
      expect(doc.peerId, equals(author));
      expect(doc.documentId, 'docId');
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

    test('exportChangesNewerThan returns only newer changes for same peer', () {
      // create three changes
      final change1 = doc.createChange(operation);
      final change2 = doc.createChange(operation);

      final version = VersionVector({author: change1.hlc});

      final newer = doc.exportChangesNewerThan(version);

      expect(newer.length, equals(1));
      expect(newer, containsAll([change2]));
    });

    test('exportChangesNewerThan with multiple peers', () {
      final authorA = PeerId.generate();
      final authorB = PeerId.generate();

      // Build manual changes from two peers and import them in current doc
      final a1 = Change(
        id: OperationId(authorA, HybridLogicalClock(l: 1, c: 1)),
        operation: operation,
        deps: {},
        author: authorA,
      );
      final a2 = Change(
        id: OperationId(authorA, HybridLogicalClock(l: 1, c: 2)),
        operation: operation,
        deps: {a1.id},
        author: authorA,
      );
      final b1 = Change(
        id: OperationId(authorB, HybridLogicalClock(l: 2, c: 1)),
        operation: operation,
        deps: {},
        author: authorB,
      );

      // Import in causal order
      expect(doc.importChanges([a1, a2, b1]), equals(3));

      // Server knows up to a1 for authorA, and nothing for authorB
      final version = VersionVector({authorA: a1.hlc});

      final newer = doc.exportChangesNewerThan(version);

      expect(newer, contains(a2));
      expect(newer, contains(b1));
      // Should not include a1
      expect(newer.contains(a1), isFalse);
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

    group('updates stream', () {
      test(
          'emits when applyChange applies (>0),'
          ' not when no-op (<=0)', () async {
        final events = <void>[];
        final sub = doc.updates.listen((_) => events.add(null));

        // apply a new change -> should emit
        final c1 = doc.createChange(operation);
        await Future<void>.delayed(Duration.zero);
        expect(events.length, 1);

        // applying duplicate change -> no emit
        final appliedAgain = doc.applyChange(c1);
        expect(appliedAgain, isFalse);
        await Future<void>.delayed(Duration.zero);
        expect(events.length, 1);

        await sub.cancel();
      });

      test(
          'emits when importChanges applies (>0),'
          ' not when applies 0', () async {
        final events = <void>[];
        final sub = doc.updates.listen((_) => events.add(null));

        final other = CRDTDocument(peerId: PeerId.generate());
        final otherHandler = TestHandler(other);
        final otherOp = TestOperation.fromHandler(otherHandler);

        // create and import 1 change -> should emit
        final c = other.createChange(otherOp);
        final applied = doc.importChanges([c]);
        expect(applied, greaterThan(0));
        await Future<void>.delayed(Duration.zero);
        expect(events.length, 1);

        // re-import same change -> 0 applied, no emit
        final appliedAgain = doc.importChanges([c]);
        expect(appliedAgain, equals(0));
        await Future<void>.delayed(Duration.zero);
        expect(events.length, 1);

        await sub.cancel();
      });

      test('emits when importSnapshot succeeds, not when rejected', () async {
        final events = <void>[];
        final sub = doc.updates.listen((_) => events.add(null));

        // Create a newer snapshot from another document
        final other = CRDTDocument(peerId: PeerId.generate());
        final otherHandler = TestHandler(other);
        final otherOp = TestOperation.fromHandler(otherHandler);

        final oldSnapshot = other.takeSnapshot();

        other.createChange(otherOp); // make snapshot newer than empty doc
        final snapNewer = other.takeSnapshot();

        // import newer -> emit
        final imported = doc.importSnapshot(snapNewer);
        expect(imported, isTrue);
        await Future<void>.delayed(Duration.zero);
        expect(events.length, 1);

        // try import older snapshot -> no emit
        final importedOld = doc.importSnapshot(oldSnapshot);
        expect(importedOld, isFalse);
        await Future<void>.delayed(Duration.zero);
        expect(events.length, 1);

        await sub.cancel();
      });

      test('emits when mergeSnapshot is called', () async {
        final events = <void>[];
        final sub = doc.updates.listen((_) => events.add(null));

        final other = CRDTDocument(peerId: PeerId.generate());
        final otherHandler = TestHandler(other);
        final otherOp = TestOperation.fromHandler(otherHandler);
        other.createChange(otherOp);
        final snap = other.takeSnapshot();

        doc.mergeSnapshot(snap);
        await Future<void>.delayed(Duration.zero);
        expect(events.length, 1);

        await sub.cancel();
      });
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

    test('should not accept snapshot not newer then current', () {
      final author1 = PeerId.generate();
      final author2 = PeerId.generate();

      final doc1 = CRDTDocument(peerId: author1);
      final handler1 = CRDTListHandler<String>(doc1, 'list');

      final doc2 = CRDTDocument(peerId: author2);

      handler1
        ..insert(0, 'Hello')
        ..insert(1, 'World');

      final snapshot1 = doc1.takeSnapshot();

      handler1
        ..insert(2, ' "Dart')
        ..insert(3, 'Flutter');

      final snapshot2 = doc1.takeSnapshot();

      final imported2 = doc2.importSnapshot(snapshot2);
      expect(imported2, isTrue);

      final imported1 = doc2.importSnapshot(snapshot1);
      expect(imported1, isFalse);
      expect(doc1.importSnapshot(snapshot1), isFalse);
    });

    test('should prune changes when merge snapshot is called', () {
      final author1 = PeerId.generate();
      final author2 = PeerId.generate();

      final doc1 = CRDTDocument(peerId: author1);
      final handler1 = CRDTListHandler<String>(doc1, 'list');

      final doc2 = CRDTDocument(peerId: author2);
      final handler2 = CRDTListHandler<String>(doc2, 'list');

      handler1
        ..insert(0, 'Hello')
        ..insert(1, 'World');

      doc2.importChanges(doc1.exportChanges());

      expect(handler2.value[0], equals('Hello'));
      expect(handler2.value[1], equals('World'));

      final snapshot = doc2.takeSnapshot();
      handler1
        ..insert(2, 'Dart')
        ..update(0, 'Hello, ');

      // should prune changes respect to the snapshot version vector
      // so the change "Hello" and "World" are pruned
      doc1.mergeSnapshot(snapshot);

      // result must be consistent also with the prune
      expect(handler1.value[0], equals('Hello, '));
      expect(handler1.value[1], equals('World'));
      expect(handler1.value[2], equals('Dart'));

      expect(doc1.exportChanges().length, equals(2));

      doc2.importChanges(doc1.exportChanges());

      expect(handler2.value[0], equals('Hello, '));
      expect(handler2.value[1], equals('World'));
      expect(handler2.value[2], equals('Dart'));
    });

    test('should prune changes when import snapshot is called', () {
      final author1 = PeerId.generate();
      final author2 = PeerId.generate();

      final doc1 = CRDTDocument(peerId: author1);
      final handler1 = CRDTListHandler<String>(doc1, 'list');

      final doc2 = CRDTDocument(peerId: author2);
      final handler2 = CRDTListHandler<String>(doc2, 'list');

      handler1
        ..insert(0, 'Hello')
        ..insert(1, 'World');

      doc2.importChanges(doc1.exportChanges());

      expect(handler2.value[0], equals('Hello'));
      expect(handler2.value[1], equals('World'));

      final snapshot = doc2.takeSnapshot();
      handler1
        ..insert(2, 'Dart')
        ..update(0, 'Hello, ');

      // should prune changes respect to the snapshot version vector
      // so the change "Hello" and "World" are pruned
      final imported = doc1.importSnapshot(snapshot);
      expect(imported, isTrue);

      // result must be consistent also with the prune
      expect(handler1.value[0], equals('Hello, '));
      expect(handler1.value[1], equals('World'));
      expect(handler1.value[2], equals('Dart'));

      expect(doc1.exportChanges().length, equals(2));

      doc2.importChanges(doc1.exportChanges());

      expect(handler2.value[0], equals('Hello, '));
      expect(handler2.value[1], equals('World'));
      expect(handler2.value[2], equals('Dart'));
    });

    test(
        'should accept changes whose dependencies were pruned '
        'by a snapshot', () {
      final serverDoc = CRDTDocument();
      final clientDoc = CRDTDocument();

      final serverHandler = CRDTListHandler<String>(serverDoc, 'todos');
      final clientHandler = CRDTListHandler<String>(clientDoc, 'todos')
        ..insert(0, 'initial');
      serverDoc
        ..importChanges(clientDoc.exportChanges())
        // Server compacts history, removing the dependency node
        ..takeSnapshot();

      // Client goes offline and generates a change referencing
      // the pruned dependency.
      clientHandler.insert(1, 'offline');

      final pendingChanges =
          clientDoc.exportChangesNewerThan(serverDoc.getVersionVector());
      expect(pendingChanges, hasLength(1));

      expect(
        () => serverDoc.applyChange(pendingChanges.first),
        returnsNormally,
      );

      expect(serverHandler.value, clientHandler.value);
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

        expect(snapshotImported, isTrue);
        expect(serverHandler.value, ['Hello']);
        expect(clientHandler.value, ['Hello', 'World']);
        expect(clientDoc.exportChanges().length, 1);

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
          equals(0),
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

    group('handlers', () {
      test('should throw on double registration', () {
        expect(
          () {
            return TestHandler(doc);
          },
          throwsA(isA<HandlerAlreadyRegisteredException>()),
        );
      });

      test('should not increment cached without a cached state', () {
        final handler = _FakeCRDTListHandler(doc, 'test-list');
        expect(handler._incrementedCount, 0);
        // cached state is never computed
        handler.insert(0, 'Hello');
        expect(handler._incrementedCount, 0);
      });

      test('should increment cached state on operation application', () {
        final handler = _FakeCRDTListHandler(doc, 'test-list');
        expect(handler._incrementedCount, 0);
        // compute cached state
        expect(handler.value, const <String>[]);
        handler
          ..insert(0, 'Hello')
          ..insert(1, 'World');
        expect(handler._incrementedCount, 2);
      });

      test(
          'should not increment cached state'
          ' if useIncrementalCacheUpdate is false', () {
        final handler = _FakeCRDTListHandler(doc, 'test-list')
          ..useIncrementalCacheUpdate = false;
        expect(handler._incrementedCount, 0);
        expect(handler.value, const <String>[]);
        handler.insert(0, 'Hello');
        expect(handler._incrementedCount, 0);
      });

      test('should remove cache if incrementalCache return null', () {
        final handler = _FakeCRDTListHandler(doc, 'test-list')
          ..useIncrementalCacheUpdate = true
          ..value;
        expect(handler._incrementedCount, 0);
        expect(handler.value, const <String>[]);

        handler.insert(0, 'Hello');
        expect(handler._incrementedCount, 1);

        handler
          ..notIncrementState = true
          // this insert will not increment the cached state
          ..insert(1, 'Dart')
          // increment state not called
          ..insert(2, 'Flutter');
        expect(handler._incrementedCount, 2);
      });

      test('should ignore old cached state', () {
        final handler = _FakeCRDTListHandler(doc, 'test-list')
          ..useIncrementalCacheUpdate = true;
        expect(handler._incrementedCount, 0);
        expect(handler.value, const <String>[]);
        handler.insert(0, 'Hello');
        expect(handler._incrementedCount, 1);
        handler
          ..useIncrementalCacheUpdate = false
          ..insert(1, 'World');
        expect(handler._incrementedCount, 1);

        // previous "insert" didn't increment cached state
        // therefore, new "insert" should not increment cached state
        handler
          ..useIncrementalCacheUpdate = true
          ..insert(2, 'Dart!');
        expect(handler._incrementedCount, 1);
        expect(handler.value, ['Hello', 'World', 'Dart!']);
      });

      test(
          'should related external handler changes '
          'invalidate the handlers cache', () {
        final handler1 = _FakeCRDTListHandler(doc, 'error-handler-1')
          ..useIncrementalCacheUpdate = true
          ..value;
        final handler2 = _FakeCRDTListHandler(doc, 'error-handler-2')
          ..useIncrementalCacheUpdate = true
          ..value;

        final otherDoc = CRDTDocument(peerId: PeerId.generate());
        final otherHandler = _FakeCRDTListHandler(otherDoc, 'error-handler-1')
          ..useIncrementalCacheUpdate = true
          ..value;

        // Initial state
        expect(handler1._incrementedCount, 0);
        expect(handler2._incrementedCount, 0);

        // Perform operations that will succeed
        handler1.insert(0, 'Hello'); // cache incremented
        handler2.insert(0, 'World'); // cache incremented
        otherHandler.insert(0, 'Other');
        expect(handler1._incrementedCount, 1);
        expect(handler2._incrementedCount, 1);

        doc.runInTransaction<void>(() {
          handler1.insert(1, 'Dart'); // cache incremented

          // contains changes for handler1 so it's cache is invalidated
          doc.importChanges(otherDoc.exportChanges());

          handler2.insert(1, 'Flutter'); // cache incremented
        });

        handler1.insert(2, 'Test'); // cache not incremented
        handler2.insert(2, 'Test2'); // cache incremented

        // Cache should be invalidated, so incremental count should not increase
        expect(handler1._incrementedCount, 2);
        // value is computed from scratch
        expect(
          handler1.value,
          containsAll(
            ['Other', 'Dart', 'Test', 'Hello'],
          ),
        );
        expect(handler2._incrementedCount, 3);
      });

      test(
          'should external actions not applied to document '
          'not affect the handlers cache', () {
        final handler1 = _FakeCRDTListHandler(doc, 'external-handler-1')
          ..useIncrementalCacheUpdate = true
          ..value;
        final handler2 = _FakeCRDTListHandler(doc, 'external-handler-2')
          ..useIncrementalCacheUpdate = true
          ..value;

        // Initial state
        expect(handler1._incrementedCount, 0);
        expect(handler2._incrementedCount, 0);

        // Perform initial operations
        handler1.insert(0, 'Hello'); // cache incremented
        handler2.insert(0, 'World');
        expect(handler1._incrementedCount, 1);
        expect(handler2._incrementedCount, 1);

        // Import external changes in a transaction
        expect(
          () => doc.runInTransaction<void>(() {
            // Perform local operations
            handler1.insert(1, 'Dart'); // cache incremented
            handler2.insert(1, 'Flutter');

            final unexpectedDep = OperationId(
              PeerId.generate(),
              HybridLogicalClock(l: 9999999, c: 9999999),
            );
            doc.applyChange(
              Change(
                author: author,
                id: OperationId(author, HybridLogicalClock(l: 1, c: 1)),
                operation: TestOperation.fromHandler(handler1),
                deps: {unexpectedDep},
              ),
            ); // throws an exception unrelated to handlers
          }),
          throwsA(isA<CrdtException>()),
        );

        handler1.insert(2, 'Test1'); // cache incremented
        handler2.insert(2, 'Test2'); // cache incremented

        expect(handler1._incrementedCount, 3);
        expect(handler2._incrementedCount, 3);
        expect(handler1.value, containsAll(['Hello', 'Dart', 'Test1']));
      });
    });

    group('transaction', () {
      test('runInTransaction batches updates and notifies only once', () async {
        final events = <void>[];
        final sub = doc.updates.listen((_) => events.add(null));
        final listHandler = CRDTListHandler<String>(doc, 'tx-list');

        // Multiple operations within a transaction should emit a single update
        doc.runInTransaction<void>(() {
          listHandler
            ..insert(0, 'a')
            ..insert(1, 'b')
            ..insert(2, 'c');
        });

        await Future<void>.delayed(Duration.zero);
        expect(events.length, 1);

        await sub.cancel();
      });

      test('runInTransaction batches import + handler ops and emits once',
          () async {
        final events = <void>[];
        final sub = doc.updates.listen((_) => events.add(null));
        final listHandler = CRDTListHandler<String>(doc, 'tx-list-2');

        // Prepare another document with a change and a snapshot
        final otherDocument = CRDTDocument(peerId: PeerId.generate());
        final otherHandler = TestHandler(otherDocument);
        final otherOp = TestOperation.fromHandler(otherHandler);
        final otherSnap = otherDocument.takeSnapshot();
        final otherChange = otherDocument.createChange(otherOp);
        expect(otherChange, isNotNull);

        // Batch import + a couple of local handler ops in a single transaction
        doc.runInTransaction<void>(() {
          final imported1 = doc.importSnapshot(otherSnap);
          expect(imported1, isTrue);

          final applied = doc.importChanges([otherChange]);
          expect(applied, greaterThan(0));

          listHandler
            ..insert(0, 'hello')
            ..insert(1, 'world');
        });

        await Future<void>.delayed(Duration.zero);
        // Only one update despite multiple operations inside the transaction
        expect(events.length, 1);

        await sub.cancel();
      });

      test(
        'runInTransaction batches import '
        '+ handler ops '
        '+ local changes and emits once',
        () async {
          final events = <void>[];
          final sub = doc.updates.listen((_) => events.add(null));
          final listHandler = CRDTListHandler<String>(doc, 'tx-list');

          // Prepare another document with a change and a snapshot
          final otherDocument = CRDTDocument(peerId: PeerId.generate());
          final otherHandler = TestHandler(otherDocument);
          final otherOp = TestOperation.fromHandler(otherHandler);
          final otherSnap = otherDocument.takeSnapshot();
          final otherChange = otherDocument.createChange(otherOp);
          expect(otherChange, isNotNull);

          // Create a local handler for generating local changes
          final localHandler = TestHandler(doc, id: 'other-local-handler');

          // Batch import + handler ops + local changes in a single transaction
          doc.runInTransaction<void>(() {
            // Import snapshot and changes from other document
            final imported1 = doc.importSnapshot(otherSnap);
            expect(imported1, isTrue);

            final applied = doc.importChanges([otherChange]);
            expect(applied, greaterThan(0));

            // Perform handler operations
            listHandler
              ..insert(0, 'hello')
              ..insert(1, 'world');

            // Create and apply local changes
            final localOp = TestOperation.fromHandler(localHandler);
            final localChange = doc.createChange(localOp);
            expect(localChange, isNotNull);
          });

          await Future<void>.delayed(Duration.zero);
          // Only one update despite multiple operations inside the transaction
          expect(events.length, 1);

          await sub.cancel();
        },
      );

      test(
          'should compound during transaction and emit compacted local changes',
          () async {
        final events = <void>[];
        final localChanges = <Change>[];

        doc.updates.listen((_) => events.add(null));
        doc.localChanges.listen(localChanges.add);

        final textHandler = CRDTTextHandler(doc, 'text');

        doc.runInTransaction<void>(() {
          textHandler
            ..insert(0, 'Hello')
            ..insert(5, ' World')
            ..delete(6, 5)
            ..insert(6, 'Dart!');
        });

        await Future<void>.delayed(Duration.zero);
        expect(events.length, 1);
        expect(localChanges.length, 1);
        expect(textHandler.value, 'Hello Dart!');
      });
    });
  });
}

class _FakeCRDTListHandler extends CRDTListHandler<String> {
  _FakeCRDTListHandler(super.doc, super.id);

  /// count of `incrementCachedState`
  var _incrementedCount = 0;

  /// `incrementCachedState` will return null
  bool notIncrementState = false;

  @override
  List<String>? incrementCachedState({
    required Operation operation,
    required List<String> state,
  }) {
    _incrementedCount++;

    if (notIncrementState) {
      return null;
    }

    return super.incrementCachedState(operation: operation, state: state);
  }
}
