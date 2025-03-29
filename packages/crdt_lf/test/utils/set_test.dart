import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
  group('setEquals', () {
    test('should be equal', () {
      expect(setEquals(Set.from([1, 2, 3]), Set.from([1, 2, 3])), isTrue);
      expect(setEquals(Set.from([1, 2, 3]), Set.from([1, 3, 2])), isTrue);
      expect(setEquals(Set.from([1, 2, 3]), Set.from({1, 3, 2})), isTrue);
    });

    test('should be unequal', () {
      expect(setEquals(Set.from([1, 2, 3]), Set.from([1, 2, 4])), isFalse);
      expect(setEquals(Set.from([1, 2, 3]), Set.from({1, 2, 4})), isFalse);
    });
  });
}
