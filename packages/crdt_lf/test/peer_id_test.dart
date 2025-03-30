import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
  group('PeerId', () {
    test('constructor creates with given id', () {
      const id = '20838a87-21f6-449c-8773-6b6b07bc0e75';
      final peerId = PeerId.parse(id);
      expect(peerId.id, equals(id));
    });

    test('generate creates valid UUID v4', () {
      final peerId = PeerId.generate();
      expect(peerId.id, matches(RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        caseSensitive: false,
      )));
    });

    test('parse accepts valid UUID v4', () {
      const validId = '84bb95b4-5fc8-4920-ae2f-e587a1e15037';
      final peerId = PeerId.parse(validId);
      expect(peerId.id, equals(validId));
    });

    test('parse throws on invalid UUID v4', () {
      const invalidIds = [
        '123e4567-e89b-02d3-a456-426614174000', // Invalid version
        '123e4567-e89b-12d3-c456-426614174000', // Invalid variant
        '123e4567-e89b-12d3-a456-42661417400',  // Too short
        '123e4567-e89b-12d3-a456-4266141740000', // Too long
        'invalid-uuid', // Invalid format
      ];

      for (final id in invalidIds) {
        expect(
          () => PeerId.parse(id),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test('toString returns the id', () {
      const id = 'd7b61211-b928-4477-8cdd-0d5a4fca9ea7';
      final peerId = PeerId.parse(id);
      expect(peerId.toString(), equals(id));
    });

    test('equality works correctly', () {
      const id = '3829d118-eb27-44e1-909c-dbd9d902973b';
      final peerId1 = PeerId.parse(id);
      final peerId2 = PeerId.parse(id);
      final peerId3 = PeerId.parse('1f178c45-2a35-4d3f-9e6c-d20b0d50e374');

      expect(peerId1, equals(peerId2));
      expect(peerId1, isNot(equals(peerId3)));
    });

    test('hashCode is consistent', () {
      const id = '5bd477be-1518-43dd-9538-9bb783ea40d3';
      final peerId1 = PeerId.parse(id);
      final peerId2 = PeerId.parse(id);
      final peerId3 = PeerId.parse('1e285489-40da-4f24-964a-cc90951d3f07');

      expect(peerId1.hashCode, equals(peerId2.hashCode));
      expect(peerId1.hashCode, isNot(equals(peerId3.hashCode)));
    });

    test('compareTo works correctly', () {
      final peerId1 = PeerId.parse('e45cc089-9fc0-48c8-97e0-f4f16e7364ed');
      final peerId2 = PeerId.parse('faa87286-2e89-40c7-aa98-c84b875dcc7c');
      final peerId3 = PeerId.parse('e45cc089-9fc0-48c8-97e0-f4f16e7364ed');

      expect(peerId1.compareTo(peerId2), lessThan(0));
      expect(peerId2.compareTo(peerId1), greaterThan(0));
      expect(peerId1.compareTo(peerId3), equals(0));
    });
  });
}
