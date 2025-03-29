import 'package:crdt_lf/src/frontiers/frontiers.dart';
import 'package:crdt_lf/src/operation/id.dart';
import 'package:crdt_lf/src/peer_id.dart';
import 'package:hlc/hlc.dart';
import 'package:test/test.dart';

void main() {
  group('Frontiers', () {
    late PeerId peerId;
    late OperationId op1;
    late OperationId op2;
    late OperationId op3;

    setUp(() {
      peerId = PeerId.parse('ea8825b4-b4ae-4d85-9b32-c78d20be213a');
      op1 = OperationId(peerId, HybridLogicalClock(l: 1, c: 1));
      op2 = OperationId(peerId, HybridLogicalClock(l: 1, c: 2));
      op3 = OperationId(peerId, HybridLogicalClock(l: 1, c: 3));
    });

    test('empty constructor creates empty frontiers', () {
      final frontiers = Frontiers();
      expect(frontiers.isEmpty, isTrue);
      expect(frontiers.length, equals(0));
    });

    test('from constructor creates frontiers with initial values', () {
      final frontiers = Frontiers.from([op1, op2]);
      expect(frontiers.isEmpty, isFalse);
      expect(frontiers.length, equals(2));
      expect(frontiers.get(), equals({op1, op2}));
    });

    test('get returns a copy of the frontiers', () {
      final frontiers = Frontiers.from([op1, op2]);
      final frontiersCopy = frontiers.get();
      expect(frontiersCopy, equals({op1, op2}));

      // Modifying the copy should not affect the original
      frontiersCopy.add(op3);
      expect(frontiers.get(), equals({op1, op2}));
    });

    test('update removes dependencies and adds new operation', () {
      final frontiers = Frontiers.from([op1, op2]);

      // op3 depends on op1 and op2
      frontiers.update(
        newOperationId: op3,
        oldDependencies: {op1, op2},
      );

      expect(frontiers.get(), equals({op3}));
    });

    test('update with no dependencies only adds new operation', () {
      final frontiers = Frontiers.from([op1]);

      frontiers.update(
        newOperationId: op2,
        oldDependencies: {},
      );

      expect(frontiers.get(), equals({op1, op2}));
    });

    test('merge combines two frontiers correctly', () {
      final frontiers1 = Frontiers.from([op1]);
      final frontiers2 = Frontiers.from([op2]);

      // op3 depends on op1 and op2
      final frontiers3 = Frontiers.from([op3]);
      frontiers3.update(
        newOperationId: op3,
        oldDependencies: {op1, op2},
      );

      frontiers1.merge(frontiers2);
      expect(frontiers1.get(), equals({op2}));

      frontiers1.merge(frontiers3);
      expect(frontiers1.get(), equals({op3}));
    });

    test('merge with empty frontiers', () {
      final frontiers1 = Frontiers.from([op1]);
      final frontiers2 = Frontiers();

      frontiers1.merge(frontiers2);
      expect(frontiers1.get(), equals({op1}));

      frontiers2.merge(frontiers1);
      expect(frontiers2.get(), equals({op1}));
    });

    test('toString returns correct string representation', () {
      final frontiers = Frontiers.from([op1, op2]);
      expect(
        frontiers.toString(),
        equals('${op1.toString()}, ${op2.toString()}'),
      );
    });

    test('equality works correctly', () {
      final frontiers1 = Frontiers.from([op1, op2]);
      final frontiers2 = Frontiers.from([op1, op2]);
      final frontiers3 = Frontiers.from([op1, op3]);

      expect(frontiers1, equals(frontiers2));
      expect(frontiers1, isNot(equals(frontiers3)));
    });

    test('hashCode is consistent with equality', () {
      final frontiers1 = Frontiers.from([op1, op2]);
      final frontiers2 = Frontiers.from([op1, op2]);
      final frontiers3 = Frontiers.from([op1, op3]);

      expect(frontiers1.hashCode, equals(frontiers2.hashCode));
      expect(frontiers1.hashCode, isNot(equals(frontiers3.hashCode)));
    });

    test('copy creates a deep copy', () {
      final frontiers1 = Frontiers.from([op1, op2]);
      final frontiers2 = frontiers1.copy();

      expect(frontiers1, equals(frontiers2));

      // Modifying one should not affect the other
      frontiers2.update(
        newOperationId: op3,
        oldDependencies: {op1, op2},
      );
      expect(frontiers1.get(), equals({op1, op2}));
      expect(frontiers2.get(), equals({op3}));
    });
  });
}
