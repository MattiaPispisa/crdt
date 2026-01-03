import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

void main() {
  group('VersionVector', () {
    test('should compare correctly', () {
      final author = PeerId.generate();
      final versionVector =
          VersionVector({author: HybridLogicalClock(l: 1, c: 1)});
      final versionVector2 =
          VersionVector({author: HybridLogicalClock(l: 1, c: 2)});

      expect(versionVector.isNewerThan(versionVector2), isFalse);
      expect(versionVector2.isNewerThan(versionVector), isTrue);
    });

    test('should compare correctly with multiple peers', () {
      final author = PeerId.generate();
      final author2 = PeerId.generate();

      final versionVector = VersionVector({
        author: HybridLogicalClock(l: 1, c: 1),
        author2: HybridLogicalClock(l: 1, c: 3),
      });

      final versionVector2 = VersionVector({
        author: HybridLogicalClock(l: 1, c: 1),
        author2: HybridLogicalClock(l: 1, c: 2),
      });

      expect(versionVector.isNewerThan(versionVector2), isTrue);
      expect(versionVector2.isNewerThan(versionVector), isFalse);
    });

    test('should compare correctly with empty version vector', () {
      final versionVector = VersionVector({});
      final versionVector2 = VersionVector({});

      expect(versionVector.isNewerThan(versionVector2), isFalse);
      expect(versionVector2.isNewerThan(versionVector), isFalse);
    });

    test('should compare correctly with strict comparison', () {
      final author = PeerId.generate();
      final author2 = PeerId.generate();

      final versionVector = VersionVector({
        author: HybridLogicalClock(l: 1, c: 1),
        author2: HybridLogicalClock(l: 1, c: 3),
      });

      final versionVector2 = VersionVector({
        author: HybridLogicalClock(l: 1, c: 1),
        author2: HybridLogicalClock(l: 1, c: 2),
      });

      expect(versionVector.isStrictlyNewerThan(versionVector2), isFalse);
      expect(versionVector2.isStrictlyNewerThan(versionVector), isFalse);
    });

    test('should compare correctly with different peers', () {
      final author = PeerId.generate();
      final author2 = PeerId.generate();

      final versionVector = VersionVector({
        author: HybridLogicalClock(l: 1, c: 1),
      });

      final versionVector2 = VersionVector({
        author2: HybridLogicalClock(l: 1, c: 1),
      });

      expect(versionVector.isStrictlyNewerThan(versionVector2), isFalse);
      expect(versionVector2.isStrictlyNewerThan(versionVector), isFalse);
    });

    test('should merge correctly', () {
      final author = PeerId.generate();
      final author2 = PeerId.generate();

      final versionVector =
          VersionVector({author: HybridLogicalClock(l: 1, c: 1)});
      final versionVector2 =
          VersionVector({author2: HybridLogicalClock(l: 1, c: 1)});

      final merged = versionVector.merged(versionVector2);
      expect(
        merged.entries.length,
        equals(2),
      );
      expect(merged.entries.first.key, equals(author));
      expect(
        merged.entries.first.value,
        equals(HybridLogicalClock(l: 1, c: 1)),
      );
      expect(merged.entries.last.key, equals(author2));
      expect(merged.entries.last.value, equals(HybridLogicalClock(l: 1, c: 1)));
    });

    test('should merge correctly with multiple peers', () {
      final author = PeerId.generate();
      final author2 = PeerId.generate();
      final author3 = PeerId.generate();

      final versionVector = VersionVector({
        author: HybridLogicalClock(l: 1, c: 1),
        author2: HybridLogicalClock(l: 1, c: 4),
        author3: HybridLogicalClock(l: 1, c: 3),
      });

      final versionVector2 = VersionVector({
        author: HybridLogicalClock(l: 1, c: 2),
        author2: HybridLogicalClock(l: 1, c: 2),
        author3: HybridLogicalClock(l: 1, c: 7),
      });

      final merged = versionVector.merged(versionVector2);
      expect(
        merged.entries.length,
        equals(3),
      );
      expect(merged.entries.first.key, equals(author));
      expect(
        merged.entries.first.value,
        equals(HybridLogicalClock(l: 1, c: 2)),
      );
      expect(merged.entries.last.key, equals(author3));
      expect(merged.entries.last.value, equals(HybridLogicalClock(l: 1, c: 7)));
    });

    test('should be immutable', () {
      final versionVector = VersionVector.immutable({});
      final author = PeerId.generate();

      expect(
        () => versionVector.update(author, HybridLogicalClock(l: 1, c: 1)),
        throwsA(isA<UnsupportedError>()),
      );

      expect(
        () => versionVector.remove([author]),
        throwsA(isA<UnsupportedError>()),
      );

      expect(
        versionVector.clear,
        throwsA(isA<UnsupportedError>()),
      );

      final vvDeep = VersionVector.immutable({
        author: HybridLogicalClock(l: 1, c: 1),
      });

      vvDeep.entries.first.value.localEvent(3);
      expect(
        vvDeep.entries.first.value,
        equals(HybridLogicalClock(l: 1, c: 1)),
      );
    });

    test('should be mutable', () {
      final author = PeerId.generate();
      final mutableVersionVector = VersionVector({});

      expect(
        () =>
            mutableVersionVector.update(author, HybridLogicalClock(l: 1, c: 1)),
        returnsNormally,
      );

      expect(
        () => mutableVersionVector.remove([author]),
        returnsNormally,
      );

      expect(
        mutableVersionVector.clear,
        returnsNormally,
      );
    });

    test('mutable() should return a mutable copy', () {
      final author = PeerId.generate();
      final source = VersionVector.immutable({
        author: HybridLogicalClock(l: 1, c: 1),
      });

      final mutableCopy = source.mutable();

      expect(
        () => mutableCopy.update(author, HybridLogicalClock(l: 2, c: 0)),
        returnsNormally,
      );

      expect(
        source[author],
        equals(HybridLogicalClock(l: 1, c: 1)),
      );

      expect(
        () => mutableCopy.remove([author]),
        returnsNormally,
      );

      expect(
        mutableCopy.clear,
        returnsNormally,
      );
    });

    test('should intersect empty vectors correctly', () {
      final intersection = VersionVector.intersection([]);
      expect(intersection.isEmpty, isTrue);
    });

    test('should intersect correctly', () {
      final author = PeerId.generate();
      final author2 = PeerId.generate();
      final author3 = PeerId.generate();

      final versionVector1 = VersionVector({
        author: HybridLogicalClock(l: 1, c: 1),
        author2: HybridLogicalClock(l: 1, c: 2),
        author3: HybridLogicalClock(l: 1, c: 3),
      });

      final versionVector2 = VersionVector({
        author: HybridLogicalClock(l: 1, c: 1),
        author2: HybridLogicalClock(l: 2, c: 2),
        author3: HybridLogicalClock(l: 4, c: 3),
      });

      final versionVector3 = VersionVector({
        author: HybridLogicalClock(l: 1, c: 0),
        author2: HybridLogicalClock(l: 1, c: 0),
      });

      final intersection = VersionVector.intersection(
        [versionVector1, versionVector2, versionVector3],
      );
      expect(intersection.entries.length, equals(2));
      expect(intersection.entries.first.key, equals(author));
      expect(
        intersection.entries.first.value,
        equals(
          HybridLogicalClock(l: 1, c: 0),
        ),
      );
      expect(intersection.entries.last.key, equals(author2));
      expect(
        intersection.entries.last.value,
        equals(
          HybridLogicalClock(l: 1, c: 0),
        ),
      );
    });

    test('should return mostOldest correctly', () {
      final author = PeerId.generate();
      final author2 = PeerId.generate();
      final author3 = PeerId.generate();

      final versionVector = VersionVector({
        author: HybridLogicalClock(l: 1, c: 1),
        author2: HybridLogicalClock(l: 2, c: 2),
        author3: HybridLogicalClock(l: 3, c: 3),
      });

      final mostOldest = versionVector.mostOldest();
      expect(mostOldest, equals(HybridLogicalClock(l: 1, c: 1)));
    });
  });
}
