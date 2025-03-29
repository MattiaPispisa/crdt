import 'package:crdt_lf/src/peer_id.dart';
import 'package:test/test.dart';

void main() {
  group('PeerId', () {
    test('constructor creates with given id', () {
      const id = '123e4567-e89b-12d3-a456-426614174000';
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
      const id = '123e4567-e89b-12d3-a456-426614174000';
      final peerId = PeerId.parse(id);
      expect(peerId.toString(), equals(id));
    });

    test('equality works correctly', () {
      const id = '123e4567-e89b-12d3-a456-426614174000';
      final peerId1 = PeerId.parse(id);
      final peerId2 = PeerId.parse(id);
      final peerId3 = PeerId.parse('123e4567-e89b-12d3-a456-426614174001');

      expect(peerId1, equals(peerId2));
      expect(peerId1, isNot(equals(peerId3)));
    });

    test('hashCode is consistent', () {
      const id = '123e4567-e89b-12d3-a456-426614174000';
      final peerId1 = PeerId.parse(id);
      final peerId2 = PeerId.parse(id);
      final peerId3 = PeerId.parse('123e4567-e89b-12d3-a456-426614174001');

      expect(peerId1.hashCode, equals(peerId2.hashCode));
      expect(peerId1.hashCode, isNot(equals(peerId3.hashCode)));
    });

    test('compareTo works correctly', () {
      final peerId1 = PeerId.parse('123e4567-e89b-12d3-a456-426614174000');
      final peerId2 = PeerId.parse('123e4567-e89b-12d3-a456-426614174001');
      final peerId3 = PeerId.parse('123e4567-e89b-12d3-a456-426614174000');

      expect(peerId1.compareTo(peerId2), lessThan(0));
      expect(peerId2.compareTo(peerId1), greaterThan(0));
      expect(peerId1.compareTo(peerId3), equals(0));
    });
  });
}
