import 'dart:typed_data';

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

    test('fromUint8List throws RangeError on negative offset', () {
      expect(
        () => OperationId.fromUint8List(
          Uint8List(OperationId.byteLength),
          offset: -1,
        ),
        throwsA(isA<RangeError>()),
      );
    });

    test('fromUint8List throws RangeError when buffer is too short', () {
      expect(
        () => OperationId.fromUint8List(Uint8List(8)),
        throwsA(isA<RangeError>()),
      );
    });

    test('fromUint8List throws RangeError when offset overflows', () {
      expect(
        () => OperationId.fromUint8List(
          Uint8List(OperationId.byteLength),
          offset: 1,
        ),
        throwsA(isA<RangeError>()),
      );
    });

    test('happenedAfterOrEqual works correctly', () {
      final operationId1 = OperationId(peerId, HybridLogicalClock(l: 1, c: 1));
      final operationId2 = OperationId(peerId, HybridLogicalClock(l: 1, c: 2));
      final operationId3 = OperationId(peerId, HybridLogicalClock(l: 1, c: 1));

      expect(operationId2.happenedAfterOrEqual(operationId1), isTrue);
      expect(operationId1.happenedAfterOrEqual(operationId2), isFalse);
      expect(operationId1.happenedAfterOrEqual(operationId3), isTrue);
    });

    // An id is also the last-writer-wins mark a stamped handler stores, so a
    // list of them has to land in one order whatever order it is given.
    test('sorts into one order whatever order it is given', () {
      final peerB = PeerId.parse('00000000-0000-4000-8000-00000000000b');
      final ids = [
        OperationId(peerB, HybridLogicalClock(l: 5, c: 3)),
        OperationId(peerId, HybridLogicalClock(l: 5, c: 3)),
        OperationId(peerId, HybridLogicalClock(l: 5, c: 4)),
        OperationId(peerB, HybridLogicalClock(l: 4, c: 9)),
      ];

      final ascending = [...ids]..sort();
      final fromReversed = [...ids.reversed]..sort();

      expect(fromReversed, equals(ascending));
      expect(ascending.first, equals(ids[3]));
      expect(ascending.last, equals(ids[2]));
    });

    group('readFromBytes', () {
      test('round-trips through a fixed 24-byte record', () {
        final id = OperationId(peerId, HybridLogicalClock(l: 123456, c: 7));
        final bytes = id.toUint8List();

        expect(bytes, hasLength(OperationId.byteLength));
        expect(OperationId.byteLength, equals(24));
        expect(OperationId.readFromBytes(bytes), equals(id));
      });

      test('reads from an offset inside a larger buffer', () {
        final id = OperationId(peerId, HybridLogicalClock(l: 42, c: 1));
        final buffer = Uint8List(OperationId.byteLength + 3)
          ..setRange(3, OperationId.byteLength + 3, id.toUint8List());

        expect(OperationId.readFromBytes(buffer, offset: 3), equals(id));
      });

      // Where `fromUint8List` blames the caller with a RangeError, this one
      // blames the input: it reads ids embedded in snapshot blobs and
      // operation bodies, where a short buffer means corrupt bytes.
      test('refuses a buffer that stops inside the record', () {
        final short = Uint8List.sublistView(
          OperationId(peerId, hlc).toUint8List(),
          0,
          OperationId.byteLength - 1,
        );

        expect(
          () => OperationId.readFromBytes(short),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => OperationId.readFromBytes(Uint8List(24), offset: -1),
          throwsA(isA<FormatException>()),
        );
      });
    });
  });
}
