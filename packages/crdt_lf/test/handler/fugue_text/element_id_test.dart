import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
  group('FugueElementID', () {
    test('should create a valid ID', () {
      final id = FugueElementID(PeerId.generate(), 1);
      expect(id.isNull, false);
      expect(id.counter, 1);
    });

    test('should create a null ID', () {
      final id = FugueElementID.nullID();
      expect(id.isNull, true);
      expect(id.counter, null);
    });

    test('should compare IDs correctly', () {
      final id1 = FugueElementID(PeerId.parse('2018cd4b-31aa-4fd6-9528-e799faa827c4'), 1);
      final id2 = FugueElementID(PeerId.parse('2018cd4b-31aa-4fd6-9528-e799faa827c4'), 2);
      final id3 = FugueElementID(PeerId.parse('af920607-d15d-4b58-90f9-53947cc87ca5'), 1);

      expect(id1.compareTo(id1), 0);
      expect(id1.compareTo(id2) < 0, true);
      expect(id2.compareTo(id1) > 0, true);
      expect(id1.compareTo(id3) < 0, true); // replica1 < replica2
    });

    test('should serialize and deserialize correctly', () {
      final id = FugueElementID(PeerId.parse('9eda8d55-f5e2-46d2-bf11-974e28fc05e6'), 1);
      final json = id.toJson();
      final deserializedId = FugueElementID.fromJson(json);

      expect(deserializedId.replicaID.toString(), '9eda8d55-f5e2-46d2-bf11-974e28fc05e6');
      expect(deserializedId.counter, 1);
    });
  });
}
