import 'dart:typed_data';

import 'package:crdt_lf/src/utils/bytes.dart';
import 'package:test/test.dart';

void main() {
  group('bytesEqual', () {
    test('same content is equal across list types', () {
      expect(bytesEqual(<int>[1, 2, 3], Uint8List.fromList([1, 2, 3])), isTrue);
    });

    test('two empty lists are equal', () {
      expect(bytesEqual(<int>[], <int>[]), isTrue);
    });

    test('different content is unequal', () {
      expect(bytesEqual(<int>[1, 2, 3], <int>[1, 2, 4]), isFalse);
    });

    test('different lengths are unequal', () {
      expect(bytesEqual(<int>[1, 2], <int>[1, 2, 3]), isFalse);
      expect(bytesEqual(<int>[1, 2, 3], <int>[1, 2]), isFalse);
    });
  });

  group('startsWithBytes', () {
    test('a real prefix is accepted', () {
      expect(startsWithBytes(<int>[1, 2, 3, 4], <int>[1, 2]), isTrue);
    });

    test('an equal list is a prefix of itself', () {
      expect(startsWithBytes(<int>[1, 2], <int>[1, 2]), isTrue);
    });

    test('an empty prefix matches anything', () {
      expect(startsWithBytes(<int>[1, 2], <int>[]), isTrue);
      expect(startsWithBytes(<int>[], <int>[]), isTrue);
    });

    test('a longer prefix is refused', () {
      expect(startsWithBytes(<int>[1, 2], <int>[1, 2, 3]), isFalse);
    });

    test('a matching length but different content is refused', () {
      expect(startsWithBytes(<int>[1, 9, 3], <int>[1, 2]), isFalse);
    });
  });
}
