import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/transaction/transaction_manager.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

import '../helpers/handler.dart';

void main() {
  group('TransactionManager', () {
    late Operation dummyOperation;

    setUp(() {
      // The manager never looks inside an operation, so any real one does.
      final doc = CRDTDocument(peerId: PeerId.generate());
      dummyOperation = TestOperation.fromHandler(TestHandler(doc, id: 'dummy'));
    });

    test('begin/commit defers and flushes updates and local changes', () {
      final emittedOperations = <Operation>[];
      var updateCount = 0;

      final manager = TransactionManager(
        flushWork: (ops, _, __, ___) {
          emittedOperations.addAll(ops);
          updateCount++;
        },
      )
        // Begin transaction
        ..begin();
      expect(manager.isInTransaction, isTrue);

      // Request updates while in transaction
      manager
        ..requestUpdate()
        ..requestUpdate();
      expect(updateCount, 0);

      // Emit local changes while in transaction
      manager.handleOperation(dummyOperation);
      expect(emittedOperations, isEmpty);
      expect(updateCount, 0);

      // Commit outermost transaction -> flush once
      manager.commit();
      expect(manager.isInTransaction, isFalse);
      expect(emittedOperations.length, 1);
      expect(updateCount, 1);
    });

    test('nested begin/commit flushes once at outer commit', () {
      final emittedOperations = <Operation>[];
      final emittedChanges = <Change>[];
      var updateCount = 0;

      final manager = TransactionManager(
        flushWork: (ops, created, ingested, ___) {
          emittedOperations.addAll(ops);
          emittedChanges
            ..addAll(created)
            ..addAll(ingested);
          updateCount++;
        },
      )
        ..begin()
        ..begin();
      expect(manager.isInTransaction, isTrue);

      manager.requestUpdate();

      final peerId = PeerId.generate();
      final dummyChange = Change(
        id: OperationId(peerId, HybridLogicalClock(l: 1, c: 1)),
        operation: dummyOperation,
        deps: {},
        author: peerId,
      );

      manager
        ..handleOperation(dummyOperation)
        ..handleAppliedChanges([dummyChange], created: true)

        // Inner commit should not flush
        ..commit();
      expect(emittedOperations, isEmpty);
      expect(emittedChanges, isEmpty);
      expect(updateCount, 0);

      // Outermost commit should flush once
      manager.commit();
      expect(emittedOperations.length, 1);
      expect(emittedChanges.length, 1);
      expect(updateCount, 1);
    });

    test('requestUpdate outside transaction emits immediately', () {
      var updateCount = 0;
      TransactionManager(
        flushWork: (_, __, ___, ____) => updateCount++,
      ).requestUpdate();
      expect(updateCount, 1);
    });

    test('handleOperation outside transaction emits immediately', () {
      var updateCount = 0;
      TransactionManager(
        flushWork: (_, __, ___, ____) => updateCount++,
      ).handleOperation(dummyOperation);
      expect(updateCount, 1);
    });

    test('handleChanges outside transaction emits immediately', () {
      var updateCount = 0;
      final peerId = PeerId.generate();
      final change = Change(
        id: OperationId(peerId, HybridLogicalClock(l: 1, c: 1)),
        operation: dummyOperation,
        deps: {},
        author: peerId,
      );
      TransactionManager(
        flushWork: (_, __, ___, ____) => updateCount++,
      ).handleAppliedChanges([change], created: true);
      expect(updateCount, 1);
    });

    test('created and ingested changes reach the flush in their own list', () {
      final flushedCreated = <Change>[];
      final flushedIngested = <Change>[];

      Change changeAt(int clock) {
        final peerId = PeerId.generate();
        return Change(
          id: OperationId(peerId, HybridLogicalClock(l: clock, c: 1)),
          operation: dummyOperation,
          deps: {},
          author: peerId,
        );
      }

      final mine = changeAt(1);
      final theirs = changeAt(2);

      final manager = TransactionManager(
        flushWork: (_, created, ingested, __) {
          flushedCreated.addAll(created);
          flushedIngested.addAll(ingested);
        },
      );

      manager.run(() {
        manager
          ..handleAppliedChanges([mine], created: true)
          ..handleAppliedChanges([theirs], created: false);
      });

      expect(flushedCreated, [mine]);
      expect(flushedIngested, [theirs]);
    });

    test('commit outside transaction throws', () {
      expect(
        () => TransactionManager(
          flushWork: (_, __, ___, ____) {},
        ).commit(),
        throwsStateError,
      );
    });
  });
}
