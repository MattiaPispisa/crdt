import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/transaction/transaction_manager.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

void main() {
  group('TransactionManager', () {
    test('begin/commit defers and flushes updates and local changes', () {
      final emittedOperations = <Operation>[];
      var updateCount = 0;

      final manager = TransactionManager(
        flushWork: (ops, _, ___) {
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
      final dummyOperation = TestOperation('dummy');

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
        flushWork: (ops, changes, ___) {
          emittedOperations.addAll(ops);
          emittedChanges.addAll(changes);
          updateCount++;
        },
      )
        ..begin()
        ..begin();
      expect(manager.isInTransaction, isTrue);

      manager.requestUpdate();

      final dummyOperation = TestOperation('dummy');
      final dummyChange = Change(
        id: OperationId(PeerId.generate(), HybridLogicalClock(l: 1, c: 1)),
        operation: dummyOperation,
        deps: {},
        author: PeerId.generate(),
      );

      manager
        ..handleOperation(dummyOperation)
        ..handleAppliedChanges([dummyChange])

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
        flushWork: (_, __, ___) => updateCount++,
      ).requestUpdate();
      expect(updateCount, 1);
    });

    test('handleOperation outside transaction emits immediately', () {
      var updateCount = 0;
      TransactionManager(
        flushWork: (_, __, ___) => updateCount++,
      ).handleOperation(TestOperation('dummy'));
      expect(updateCount, 1);
    });

    test('handleChanges outside transaction emits immediately', () {
      var updateCount = 0;
      final change = Change(
        id: OperationId(PeerId.generate(), HybridLogicalClock(l: 1, c: 1)),
        operation: TestOperation('dummy'),
        deps: {},
        author: PeerId.generate(),
      );
      TransactionManager(
        flushWork: (_, __, ___) => updateCount++,
      ).handleAppliedChanges([change]);
      expect(updateCount, 1);
    });

    test('commit outside transaction throws', () {
      expect(
        () => TransactionManager(
          flushWork: (_, __, ___) {},
        ).commit(),
        throwsStateError,
      );
    });
  });
}

// Minimal Operation used by TransactionManager tests
class TestOperation extends Operation {
  TestOperation(String handlerId)
      : super(
          type: OperationType.fromPayload('Test:update'),
          id: handlerId,
        );
}
