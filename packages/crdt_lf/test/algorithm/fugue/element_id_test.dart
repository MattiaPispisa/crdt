import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
  group('FugueElementID', () {
    test('nullID creates a null ID', () {
      final id = FugueElementID.nullID();
      expect(id.isNull, isTrue);
      expect(id.counter, isNull);
    });

    test('constructor creates a valid ID', () {
      final peerId = PeerId.parse('2ff4de6c-5add-42b6-b5f5-e6b7404cbf68');
      final id = FugueElementID(peerId, 1);
      expect(id.isNull, isFalse);
      expect(id.counter, equals(1));
      expect(id.replicaID, equals(peerId));
    });

    test('compareTo handles null IDs', () {
      final nullId = FugueElementID.nullID();
      final peerId = PeerId.parse('203453fc-8409-4ed4-8c1d-83951c613949');
      final validId = FugueElementID(peerId, 1);

      expect(nullId.compareTo(nullId), equals(0));
      expect(nullId.compareTo(validId), equals(-1));
      expect(validId.compareTo(nullId), equals(1));
    });

    test('compareTo compares by replicaID first', () {
      final peerId1 = PeerId.parse('d5e9dc8d-9192-433c-851b-a852f03caf0c');
      final peerId2 = PeerId.parse('8893f53e-df86-4b15-977e-eca209f0bee9');
      final id1 = FugueElementID(peerId1, 1);
      final id2 = FugueElementID(peerId2, 1);

      expect(id1.compareTo(id2), isNot(equals(0)));
    });

    test('compareTo compares by counter when replicaIDs are equal', () {
      final peerId = PeerId.parse('5793b4b7-52f9-4d64-ae17-86161ee30e65');
      final id1 = FugueElementID(peerId, 1);
      final id2 = FugueElementID(peerId, 2);

      expect(id1.compareTo(id2), equals(-1));
      expect(id2.compareTo(id1), equals(1));
    });

    test('parse creates ID from string', () {
      final id = FugueElementID.parse('5793b4b7-52f9-4d64-ae17-86161ee30e65:1');
      expect(id.replicaID.toString(), equals('5793b4b7-52f9-4d64-ae17-86161ee30e65'));
      expect(id.counter, equals(1));
    });

    test('parse handles null ID', () {
      final id = FugueElementID.parse('null');
      expect(id.isNull, isTrue);
    });

    test('parse throws on invalid format', () {
      expect(
        () => FugueElementID.parse('invalid'),
        throwsFormatException,
      );
    });

    test('toJson serializes ID to JSON', () {
      final peerId = PeerId.parse('2ff4de6c-5add-42b6-b5f5-e6b7404cbf68');
      final id = FugueElementID(peerId, 1);
      final json = id.toJson();

      expect(json['replicaID'], equals('2ff4de6c-5add-42b6-b5f5-e6b7404cbf68'));
      expect(json['counter'], equals(1));
    });

    test('fromJson creates ID from JSON', () {
      final json = {
        'replicaID': '2ff4de6c-5add-42b6-b5f5-e6b7404cbf68',
        'counter': 1,
      };

      final id = FugueElementID.fromJson(json);
      expect(id.replicaID.toString(), equals('2ff4de6c-5add-42b6-b5f5-e6b7404cbf68'));
      expect(id.counter, equals(1));
    });

    test('fromJson handles null counter', () {
      final json = {
        'replicaID': '',
        'counter': null,
      };

      final id = FugueElementID.fromJson(json);
      expect(id.isNull, isTrue);
    });

    test('toString returns string representation', () {
      final peerId = PeerId.parse('2ff4de6c-5add-42b6-b5f5-e6b7404cbf68');
      final id = FugueElementID(peerId, 1);
      expect(id.toString(), equals('2ff4de6c-5add-42b6-b5f5-e6b7404cbf68:1'));
    });

    test('toString returns "null" for null ID', () {
      final id = FugueElementID.nullID();
      expect(id.toString(), equals('null'));
    });

    test('equals and hashCode work correctly', () {
      final peerId = PeerId.parse('2ff4de6c-5add-42b6-b5f5-e6b7404cbf68');
      final id1 = FugueElementID(peerId, 1);
      final id2 = FugueElementID(peerId, 1);
      final id3 = FugueElementID(peerId, 2);

      expect(id1 == id2, isTrue);
      expect(id1 == id3, isFalse);
      expect(id1.hashCode, equals(id2.hashCode));
      expect(id1.hashCode, isNot(equals(id3.hashCode)));
    });
  });
}
