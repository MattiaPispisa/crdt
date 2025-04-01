import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

void main() {
  group('OperationId', () {
    late PeerId peerId;
    late HybridLogicalClock hlc;

    setUp(() {
      peerId = PeerId.parse('1c8e0bd3-174e-4d2b-b1ea-eabf98a299cf');
      hlc = HybridLogicalClock(l: 1, c: 2);
    });

    test('constructor creates with given peerId and hlc', () {
      final operationId = OperationId(peerId, hlc);
      expect(operationId.peerId, equals(peerId));
      expect(operationId.hlc, equals(hlc));
    });

    test('parse accepts valid operation id string', () {
      const validString = '1c8e0bd3-174e-4d2b-b1ea-eabf98a299cf@1.2';
      final operationId = OperationId.parse(validString);
      expect(operationId.peerId, equals(peerId));
      expect(operationId.hlc, equals(hlc));
    });

    test('parse throws on invalid format', () {
      const invalidStrings = [
        'invalid@1.2', // Invalid peer ID
        '123e4567-e89b-12d3-a456-426614174000@invalid', // Invalid HLC
        '123e4567-e89b-12d3-a456-4266141740001.2', // Missing @
        '123e4567-e89b-12d3-a456-426614174000@1.2@extra', // Extra @
      ];

      for (final str in invalidStrings) {
        expect(
          () => OperationId.parse(str),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('toString returns correct format', () {
      final operationId = OperationId(peerId, hlc);
      expect(
        operationId.toString(),
        equals('1c8e0bd3-174e-4d2b-b1ea-eabf98a299cf@1.2'),
      );
    });

    test('equality works correctly', () {
      final operationId1 = OperationId(peerId, hlc);
      final operationId2 = OperationId(peerId, hlc);
      final operationId3 = OperationId(
        PeerId.parse('c7b4d5aa-06a3-47d1-9dd1-5623bacbccfd'),
        hlc,
      );
      final operationId4 = OperationId(
        peerId,
        HybridLogicalClock(l: 1, c: 3),
      );

      expect(operationId1, equals(operationId2));
      expect(operationId1, isNot(equals(operationId3)));
      expect(operationId1, isNot(equals(operationId4)));
    });

    test('hashCode is consistent', () {
      final operationId1 = OperationId(peerId, hlc);
      final operationId2 = OperationId(peerId, hlc);
      final operationId3 = OperationId(
        PeerId.parse('38b03782-8f4a-4698-9c48-8b837cf608f5'),
        hlc,
      );
      final operationId4 = OperationId(
        peerId,
        HybridLogicalClock(l: 1, c: 3),
      );

      expect(operationId1.hashCode, equals(operationId2.hashCode));
      expect(operationId1.hashCode, isNot(equals(operationId3.hashCode)));
      expect(operationId1.hashCode, isNot(equals(operationId4.hashCode)));
    });

    test('compareTo works correctly', () {
      final operationId1 = OperationId(peerId, HybridLogicalClock(l: 1, c: 1));
      final operationId2 = OperationId(peerId, HybridLogicalClock(l: 1, c: 2));
      final operationId3 = OperationId(peerId, HybridLogicalClock(l: 1, c: 1));
      final operationId4 = OperationId(
        PeerId.parse('4cc91736-39b5-4b72-a531-c330047eff09'),
        HybridLogicalClock(l: 1, c: 1),
      );

      expect(operationId1.compareTo(operationId2), lessThan(0));
      expect(operationId2.compareTo(operationId1), greaterThan(0));
      expect(operationId1.compareTo(operationId3), equals(0));
      expect(operationId1.compareTo(operationId4), lessThan(0));
    });

    test('happenedBefore works correctly', () {
      final operationId1 = OperationId(peerId, HybridLogicalClock(l: 1, c: 1));
      final operationId2 = OperationId(peerId, HybridLogicalClock(l: 1, c: 2));
      final operationId3 = OperationId(peerId, HybridLogicalClock(l: 1, c: 1));

      expect(operationId1.happenedBefore(operationId2), isTrue);
      expect(operationId2.happenedBefore(operationId1), isFalse);
      expect(operationId1.happenedBefore(operationId3), isFalse);
    });

    test('happenedAfter works correctly', () {
      final operationId1 = OperationId(peerId, HybridLogicalClock(l: 1, c: 1));
      final operationId2 = OperationId(peerId, HybridLogicalClock(l: 1, c: 2));
      final operationId3 = OperationId(peerId, HybridLogicalClock(l: 1, c: 1));

      expect(operationId2.happenedAfter(operationId1), isTrue);
      expect(operationId1.happenedAfter(operationId2), isFalse);
      expect(operationId1.happenedAfter(operationId3), isFalse);
    });

    test('happenedAfterOrEqual works correctly', () {
      final operationId1 = OperationId(peerId, HybridLogicalClock(l: 1, c: 1));
      final operationId2 = OperationId(peerId, HybridLogicalClock(l: 1, c: 2));
      final operationId3 = OperationId(peerId, HybridLogicalClock(l: 1, c: 1));

      expect(operationId2.happenedAfterOrEqual(operationId1), isTrue);
      expect(operationId1.happenedAfterOrEqual(operationId2), isFalse);
      expect(operationId1.happenedAfterOrEqual(operationId3), isTrue);
    });
  });
}
