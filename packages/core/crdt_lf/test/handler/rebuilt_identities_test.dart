import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

/// The mixin on its own, so the chain rules are pinned without going through
/// a handler.
final class _Chain with RebuiltIdentities<String> {}

void main() {
  group('RebuiltIdentities', () {
    test('an unknown key stands for itself', () {
      final chain = _Chain();

      expect(chain.hasRebuiltIdentities, isFalse);
      expect(chain.latestOf('a'), 'a');
      expect(chain.chainOf('a'), ['a']);
    });

    test('follows a chain of rebuilds to its end', () {
      final chain = _Chain()
        ..noteRebuilt('a', 'b')
        ..noteRebuilt('b', 'c');

      expect(chain.hasRebuiltIdentities, isTrue);
      expect(chain.latestOf('a'), 'c');
      expect(chain.chainOf('a'), ['a', 'b', 'c']);
      expect(chain.chainOf('b'), ['b', 'c']);
      expect(chain.chainOf('c'), ['c']);
    });

    test('a later link replaces the one it was given', () {
      final chain = _Chain()
        ..noteRebuilt('a', 'b')
        ..noteRebuilt('a', 'c');

      expect(chain.latestOf('a'), 'c');
    });

    test('clearRebuiltIdentities forgets every link', () {
      final chain = _Chain()
        ..noteRebuilt('a', 'b')
        ..clearRebuiltIdentities();

      expect(chain.hasRebuiltIdentities, isFalse);
      expect(chain.latestOf('a'), 'a');
    });

    test('expandChains returns null while nothing has moved', () {
      final chain = _Chain();

      expect(chain.expandChains(['a', 'b']), isNull);
      // A link that touches none of the keys still leaves them alone.
      chain.noteRebuilt('z', 'y');
      expect(chain.expandChains(['a', 'b']), isNull);
    });

    test('expandChains gives every key its whole chain, once', () {
      final chain = _Chain()
        ..noteRebuilt('a', 'b')
        ..noteRebuilt('b', 'c');

      // 'b' is already inside the chain of 'a': naming both must not name it
      // twice, or a caller comparing lengths would see a move that is not one.
      expect(chain.expandChains(['a', 'b']), ['a', 'b', 'c']);
      expect(chain.expandChains(['a', 'd']), ['a', 'b', 'c', 'd']);
    });

    test('latestOfAll returns null while nothing has moved', () {
      final chain = _Chain()..noteRebuilt('z', 'y');

      expect(chain.latestOfAll(['a', 'b']), isNull);
      expect(chain.latestOfAll(['a', 'z']), ['a', 'y']);
    });

    test('commitRestores pairs what an inverse restores by position', () {
      final chain = _Chain();
      final inverse = Object();

      chain
        ..noteRestores(inverse, ['a', 'b'])
        ..commitRestores(inverse, ['x', 'y']);

      expect(chain.latestOf('a'), 'x');
      expect(chain.latestOf('b'), 'y');
    });

    test('commitRestores does nothing for an inverse that restores nothing',
        () {
      final chain = _Chain()..commitRestores(Object(), ['x']);

      expect(chain.hasRebuiltIdentities, isFalse);
    });

    test('drops the oldest link past the limit', () {
      final chain = _Chain();
      // One past the cap, so exactly the first link is dropped.
      for (var i = 0; i <= RebuiltIdentities.maxRebuilt; i++) {
        chain.noteRebuilt('k$i', 'v$i');
      }

      expect(chain.latestOf('k0'), 'k0', reason: 'the oldest link is gone');
      expect(chain.latestOf('k1'), 'v1');
      expect(
        chain.latestOf('k${RebuiltIdentities.maxRebuilt}'),
        'v${RebuiltIdentities.maxRebuilt}',
      );
    });
  });
}
