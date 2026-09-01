import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

import '../helpers/handler.dart';

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

    /// A fresh operation for every change.
    ///
    /// One operation belongs to one change — the change takes its id — so a
    /// test that wants two changes has to build two operations.
    Operation newOperation() => TestOperation.fromHandler(handler);

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
        ' provided peerId, id and initial clock', () {
      final doc = CRDTDocument(
        peerId: author,
        documentId: 'docId',
        initialClock: HybridLogicalClock(l: 1, c: 3),
      );
      expect(doc.peerId, equals(author));
      expect(doc.documentId, 'docId');
      expect(doc.hlc, equals(HybridLogicalClock(l: 1, c: 3)));
    });

    test('document should be empty', () {
      final doc = CRDTDocument(peerId: author);
      expect(doc.isEmpty, isTrue);
    });

    test('createChange creates and applies a new change', () {
      final change = doc.createChange(operation);
      expect(change.author, equals(author));
      expect(change.payloadBytes(), equals(operation.toBytes()));
      expect(doc.version, equals({change.id}));
    });

    test('clock increment on createChange', () {
      doc.createChange(newOperation());
      final clock1 = doc.hlc;
      doc.createChange(newOperation());
      final clock2 = doc.hlc;

      expect(clock1, isNot(equals(clock2)));
      expect(clock1.happenedBefore(clock2), isTrue);
    });

    test('prepareMutation spends a clock value without writing anything', () {
      // It exists so two documents can be brought to the same tick on purpose
      // — a tie in the clock is otherwise a once-a-year race. It must move the
      // clock and nothing else.
      final before = doc.hlc;

      doc.prepareMutation();

      expect(before.happenedBefore(doc.hlc), isTrue);
      expect(doc.version, isEmpty);
      expect(doc.isEmpty, isTrue);
    });

    test('createChange refuses an operation that already has a change', () {
      // The stamp an operation carries is the id of the change that carries
      // it, and it is what every last-writer-wins comparison reads. Letting one
      // operation into two changes would put the same mark on both.
      doc.createChange(operation);

      expect(() => doc.createChange(operation), throwsStateError);
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
      final change1 = doc.createChange(newOperation());
      final change2 = doc.createChange(newOperation());

      final changes = doc.exportChanges();
      expect(changes.length, equals(2));
      expect(changes, containsAll([change1, change2]));
    });

    test('exportChanges returns changes after specified version', () {
      final change1 = doc.createChange(newOperation());
      final change2 = doc.createChange(newOperation());
      final change3 = doc.createChange(newOperation());

      final changes = doc.exportChanges(from: {change1.id});
      expect(changes.length, equals(2));
      expect(changes, containsAll([change2, change3]));
    });

    test('exportChangesNewerThan returns only newer changes for same peer', () {
      // create three changes
      final change1 = doc.createChange(newOperation());
      final change2 = doc.createChange(newOperation());

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
      final id1 = OperationId(author, HybridLogicalClock(l: 1, c: 1));
      final id2 = OperationId(author, HybridLogicalClock(l: 1, c: 2));

      final change1 = Change(
        id: id1,
        operation: operation,
        deps: {id2},
        author: author,
      );

      final change2 = Change(
        id: id2,
        operation: operation,
        deps: {id1},
        author: author,
      );

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
      doc.createChange(newOperation());

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
      doc.createChange(newOperation());
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

    group('snapshot', () {
      test('importing a snapshot advances the clock past its version vector',
          () {
        final peerId = PeerId.generate();
        // A clock ahead of the wall clock: the physical time cannot mask a
        // logical clock that restarts.
        final source = CRDTDocument(
          peerId: peerId,
          initialClock: HybridLogicalClock(
            l: DateTime.now().millisecondsSinceEpoch + 60000,
            c: 0,
          ),
        );
        CRDTListHandler<String>(source, 'list')
          ..insert(0, 'a')
          ..insert(1, 'b')
          ..insert(2, 'c');
        final snapshot = source.takeSnapshot();

        // A document rebuilt from the snapshot alone has no changes to
        // advance its clock, so it would otherwise restart from zero and
        // reissue operation ids its peers already hold.
        final reloaded = CRDTDocument(peerId: peerId);
        final reloadedList = CRDTListHandler<String>(reloaded, 'list');
        reloaded.importSnapshot(snapshot);
        expect(reloadedList.value, equals(['a', 'b', 'c']));

        reloadedList.insert(3, 'd');
        final change = reloaded.exportChanges().single;
        expect(change.hlc > source.getVersionVector()[peerId]!, isTrue);

        // A peer that holds the original history accepts the new change.
        final peer = CRDTDocument(peerId: PeerId.generate());
        final peerList = CRDTListHandler<String>(peer, 'list');
        peer
          ..mergeSnapshot(snapshot, pruneHistory: false)
          ..importChanges([change]);
        expect(peerList.value, equals(['a', 'b', 'c', 'd']));
      });

      test('safe pruning, should conserve changes', () {
        CRDTListHandler<String>(doc, 'list')
          ..insert(0, 'Hello')
          ..insert(1, 'World');

        expect(doc.exportChanges(), hasLength(2));
        doc.takeSnapshot(pruneHistory: false);
        final changes = doc.exportChanges();
        expect(changes, hasLength(2));
      });

      test('safe pruning, should garbage collect correctly', () {
        CRDTListHandler<String>(doc, 'list')
          ..insert(0, 'Hello')
          ..insert(1, 'World');
        doc.takeSnapshot(pruneHistory: false);

        expect(doc.exportChanges(), hasLength(2));

        doc.garbageCollect(doc.getVersionVector());
        expect(doc.exportChanges(), hasLength(0));
      });

      test('safe pruning, should preserve history because no snapshot is taken',
          () {
        CRDTListHandler<String>(doc, 'list')
          ..insert(0, 'Hello')
          ..insert(1, 'World');

        expect(doc.exportChanges(), hasLength(2));
        doc.garbageCollect(doc.getVersionVector());
        expect(doc.exportChanges(), hasLength(2));
      });

      test('safe pruning, should import correctly', () {
        CRDTListHandler<String>(doc, 'list')
          ..insert(0, 'Hello')
          ..insert(1, 'World');

        expect(doc.exportChanges(), hasLength(2));
        final snapshot = doc.takeSnapshot(pruneHistory: false);
        final changes = doc.exportChanges();
        expect(changes, hasLength(2));

        final doc2 = CRDTDocument();
        final listDoc2 = CRDTListHandler<String>(doc2, 'list');

        final doc3 = CRDTDocument();
        final listDoc3 = CRDTListHandler<String>(doc3, 'list');

        final imported2 = doc2.import(
          changes: changes,
          pruneHistory: false,
        );
        final imported3 = doc3.import(
          snapshot: snapshot,
          changes: changes,
        );

        expect(
          imported2,
          equals(2),
          reason: 'doc2 does not import snapshot but '
              'changes contains the entire history',
        );
        expect(
          imported3,
          equals(0),
          reason: 'doc3 imports snapshot and '
              'all changes remaining consistent',
        );
        expect(doc2.exportChanges(), hasLength(2));
        expect(doc3.exportChanges(), hasLength(0));
        expect(listDoc2.value, ['Hello', 'World']);
        expect(listDoc3.value, ['Hello', 'World']);

        // import with snapshot only (no changes argument)
        final doc5 = CRDTDocument();
        CRDTListHandler<String>(doc5, 'list');
        expect(doc5.import(snapshot: snapshot), equals(0));
        expect(doc5.exportChanges(), isEmpty);
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

      // import() with an older snapshot should return -1
      final doc3 = CRDTDocument(peerId: author2);
      CRDTListHandler<String>(doc3, 'list');
      doc3.importSnapshot(snapshot2);
      expect(doc3.import(snapshot: snapshot1), equals(-1));
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
        ..createChange(newOperation())
        ..createChange(newOperation());

      expect(
        doc.toString(),
        equals(
          'CRDTDocument(peerId: $author, changes: 2, version: 1 frontiers)',
        ),
      );
    });

    group('binary round-trips', () {
      test('export and import work correctly', () {
        doc
          ..createChange(newOperation())
          ..createChange(newOperation());

        final data = doc.binaryExportChanges();
        final newDoc = CRDTDocument();
        final imported = newDoc.binaryImportChanges(data);

        expect(imported, equals(2));
        expect(newDoc.version, equals(doc.version));
      });

      test('export/import v2 syncs text changes', () {
        final doc1 = CRDTDocument(peerId: PeerId.generate());
        final doc2 = CRDTDocument(peerId: PeerId.generate());

        final t1 = CRDTTextHandler(doc1, 'text');
        final t2 = CRDTTextHandler(doc2, 'text');

        t1
          ..insert(0, 'Hello')
          ..insert(5, ' World');

        final bytes = doc1.binaryExportChanges();
        final applied = doc2.binaryImportChanges(Uint8List.fromList(bytes));
        expect(applied, greaterThan(0));

        expect(t2.value, equals(t1.value));
      });

      test('export/import v2 syncs multiple handler types together', () {
        final doc1 = CRDTDocument(peerId: PeerId.generate());
        final doc2 = CRDTDocument(peerId: PeerId.generate());

        final text1 = CRDTTextHandler(doc1, 'text');
        final fugue1 = CRDTFugueTextHandler(doc1, 'fugue');
        final list1 = CRDTListHandler<String>(doc1, 'list');
        final map1 = CRDTORMapHandler<String, int>(doc1, 'or_map');

        final text2 = CRDTTextHandler(doc2, 'text');
        final fugue2 = CRDTFugueTextHandler(doc2, 'fugue');
        final list2 = CRDTListHandler<String>(doc2, 'list');
        final map2 = CRDTORMapHandler<String, int>(doc2, 'or_map');

        text1.insert(0, 'plain');
        fugue1
          ..insert(0, 'fugue')
          ..delete(1, 2)
          ..insert(0, 'Z');
        list1
          ..insert(0, 'a')
          ..insert(1, 'b');
        map1
          ..put('count', 1)
          ..put('total', 99);

        final bytes = doc1.binaryExportChanges();
        doc2.binaryImportChanges(Uint8List.fromList(bytes));

        expect(text2.value, equals(text1.value));
        expect(fugue2.value, equals(fugue1.value));
        expect(list2.value, equals(list1.value));
        expect(map2.value, equals(map1.value));
      });

      test('binaryImportChanges rejects unsupported framing version', () {
        final doc1 = CRDTDocument(peerId: PeerId.generate());
        final t1 = CRDTTextHandler(doc1, 'text')..insert(0, 'hello');

        final exported = Uint8List.fromList(doc1.binaryExportChanges());
        // Layout: "CRDTLF"(6 bytes) + version(u8) + ...
        // Corrupt the version byte to an unsupported value.
        exported[6] = 99;

        final doc2 = CRDTDocument(peerId: PeerId.generate());
        CRDTTextHandler(doc2, 'text');
        expect(
          () => doc2.binaryImportChanges(exported),
          throwsA(isA<FormatException>()),
        );
        // The original handler is untouched.
        expect(t1.value, equals('hello'));
      });

      test('binaryImportChanges rejects empty/short buffer', () {
        final doc = CRDTDocument(peerId: PeerId.generate());
        CRDTTextHandler(doc, 'text');
        expect(
          () => doc.binaryImportChanges(Uint8List(0)),
          throwsA(isA<FormatException>()),
        );
      });
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
        expect(doc.registeredHandlers, contains('test-handler'));
        expect(
          () {
            return TestHandler(doc);
          },
          throwsA(isA<HandlerAlreadyRegisteredException>()),
        );
      });

      group('revision', () {
        test('grows on local edits and on imported changes', () {
          final a = CRDTDocument(peerId: PeerId.generate());
          final listA = CRDTListHandler<String>(a, 'x');
          expect(a.revisionForHandler('x'), 0);

          listA
            ..insert(0, 'a')
            ..insert(1, 'b');
          final afterLocal = a.revisionForHandler('x');
          expect(afterLocal, greaterThan(0));

          // A remote peer edits the same handler id; importing its changes
          // bumps the revision too.
          final b = CRDTDocument(peerId: PeerId.generate());
          CRDTListHandler<String>(b, 'x').insert(0, 'c');
          a.importChanges(b.exportChanges());
          expect(a.revisionForHandler('x'), greaterThan(afterLocal));
        });

        test('is unaffected by an unrelated handler', () {
          final a = CRDTDocument(peerId: PeerId.generate());
          CRDTListHandler<String>(a, 'x');
          final listY = CRDTListHandler<String>(a, 'y')..insert(0, 'y0');

          expect(a.revisionForHandler('x'), 0);
          final y1 = a.revisionForHandler('y');
          expect(y1, greaterThan(0));
          listY.insert(1, 'y1');
          expect(a.revisionForHandler('x'), 0); // still unaffected
          expect(a.revisionForHandler('y'), greaterThan(y1));
        });

        test(
          'a snapshot import can change a handler value while its change count '
          'stays constant — revisionForHandler catches it',
          () {
            // Peer B edits handler "x" and snapshots it.
            final b = CRDTDocument(peerId: PeerId.generate());
            CRDTListHandler<String>(b, 'x').insert(0, 'a');
            final snapshot = b.takeSnapshot();

            // Peer A registers "x" but never edits it: zero changes for "x".
            final a = CRDTDocument(peerId: PeerId.generate());
            final listA = CRDTListHandler<String>(a, 'x');
            expect(listA.value, isEmpty);
            expect(a.changeCountForHandler('x'), 0);
            expect(a.revisionForHandler('x'), 0);

            // Importing the snapshot changes the value...
            expect(a.importSnapshot(snapshot), isTrue);
            expect(listA.value, ['a']);
            // ...the change count is unchanged (nothing was added)...
            expect(a.changeCountForHandler('x'), 0);
            // ...but the revision grew: a reactive binding sees the update.
            expect(a.revisionForHandler('x'), greaterThan(0));
          },
        );

        test('mergeSnapshot bumps only the handlers carried by the snapshot',
            () {
          final a = CRDTDocument(peerId: PeerId.generate());
          CRDTListHandler<String>(a, 'x');
          CRDTListHandler<String>(a, 'y');

          final b = CRDTDocument(peerId: PeerId.generate());
          CRDTListHandler<String>(b, 'x').insert(0, 'z');

          a.mergeSnapshot(b.takeSnapshot(), pruneHistory: false);
          expect(a.revisionForHandler('x'), greaterThan(0));
          expect(a.revisionForHandler('y'), 0);
        });

        test('takeSnapshot does not bump: observable state is unchanged', () {
          final a = CRDTDocument(peerId: PeerId.generate());
          CRDTListHandler<String>(a, 'x').insert(0, 'a');

          final before = a.revisionForHandler('x');
          a.takeSnapshot(pruneHistory: false);
          expect(a.revisionForHandler('x'), before);
        });

        test('never decreases when history pruning shrinks the change count',
            () {
          final a = CRDTDocument(peerId: PeerId.generate());
          final listA = CRDTListHandler<String>(a, 'x')
            ..insert(0, 'a')
            ..insert(1, 'b');

          final countBefore = a.changeCountForHandler('x');
          final revBefore = a.revisionForHandler('x');
          expect(countBefore, greaterThan(0));

          // Pruning removes the handler's changes from the store...
          a.takeSnapshot();
          expect(a.changeCountForHandler('x'), lessThan(countBefore));
          // ...but the revision is monotonic, so a reactive binding cannot be
          // fooled by the count winding back (ABA).
          expect(a.revisionForHandler('x'), revBefore);

          listA.insert(2, 'c');
          expect(a.revisionForHandler('x'), greaterThan(revBefore));
        });
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

    group('dispose', () {
      test('should set isDisposed', () {
        expect(doc.isDisposed, isFalse);
        doc.dispose();
        expect(doc.isDisposed, isTrue);
      });
      test('dispose should be idempotent', () {
        expect(() => doc.dispose(), returnsNormally);
        expect(
          () => doc.dispose(),
          returnsNormally,
          reason: 'should be idempotent, second call should do nothing',
        );
      });

      test('"write" operations should throw when the document is disposed', () {
        final doc2 = CRDTDocument();
        CRDTListHandler<String>(doc2, 'list')
          ..insert(0, 'Hello')
          ..insert(1, 'World');
        final doc2Changes = doc2.exportChanges();
        final doc2BinaryChanges = doc2.binaryExportChanges();
        final doc2Snap = doc2.takeSnapshot();

        final list = CRDTListHandler<String>(doc, 'list');
        doc.dispose();

        expect(
          () => list.insert(0, 'Hello'),
          throwsA(isA<DocumentDisposedException>()),
        );
        expect(
          () => doc.binaryImportChanges(doc2BinaryChanges),
          throwsA(isA<DocumentDisposedException>()),
        );
        expect(
          () => doc.import(changes: doc2Changes, snapshot: doc2Snap),
          throwsA(isA<DocumentDisposedException>()),
        );
        expect(
          () => doc.importChanges(doc2Changes),
          throwsA(isA<DocumentDisposedException>()),
        );
        expect(
          () => doc.mergeSnapshot(doc2Snap),
          throwsA(isA<DocumentDisposedException>()),
        );
        expect(
          () => doc.importSnapshot(doc2Snap),
          throwsA(isA<DocumentDisposedException>()),
        );
        expect(
          () => doc.createChange(operation),
          throwsA(isA<DocumentDisposedException>()),
        );
        expect(
          () => doc.takeSnapshot(),
          throwsA(isA<DocumentDisposedException>()),
        );
        expect(
          () => doc.applyChange(
            Change(
              author: author,
              id: OperationId(author, HybridLogicalClock(l: 1, c: 1)),
              operation: TestOperation.fromHandler(list),
              deps: {},
            ),
          ),
          throwsA(isA<DocumentDisposedException>()),
        );
        expect(
          () => doc.runInTransaction<void>(() {
            list.insert(0, 'Hello');
          }),
          throwsA(isA<DocumentDisposedException>()),
        );
        expect(
          () => CRDTListHandler<String>(doc, 'second-list'),
          throwsA(isA<DocumentDisposedException>()),
        );
        expect(
          () => doc.prepareMutation(),
          throwsA(isA<DocumentDisposedException>()),
        );
        expect(
          () => doc.registerOperation(operation),
          throwsA(isA<DocumentDisposedException>()),
        );
        expect(
          () => doc.garbageCollect(doc2.getVersionVector()),
          throwsA(isA<DocumentDisposedException>()),
        );
        expect(
          doc.reconstruct,
          throwsA(isA<DocumentDisposedException>()),
        );
      });
    });
  });
}
