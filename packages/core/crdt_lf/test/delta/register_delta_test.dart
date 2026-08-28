import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
  group('RegisterDelta', () {
    test('apply answers the current value', () {
      const delta = RegisterDelta<String>(previous: 'old', current: 'new');

      expect(delta.apply('old'), 'new');
    });

    test('a write that changes nothing is empty', () {
      const delta = RegisterDelta<String>(previous: 'same', current: 'same');

      expect(delta.isEmpty, isTrue);
    });

    test('compose keeps the two ends', () {
      const a = RegisterDelta<String>(previous: 'one', current: 'two');
      const b = RegisterDelta<String>(previous: 'two', current: 'three');

      expect(
        a.compose(b),
        const RegisterDelta<String>(previous: 'one', current: 'three'),
      );
    });
  });

  group('RegisterDelta value semantics', () {
    test('a delta whose ends match moves nothing', () {
      const delta = RegisterDelta<String>(previous: 'a', current: 'a');

      expect(delta.isEmpty, isTrue);
      expect(delta.isNotEmpty, isFalse);
    });

    test('a delta whose ends differ moves something', () {
      const delta = RegisterDelta<String>(previous: 'a', current: 'b');

      expect(delta.isEmpty, isFalse);
      expect(delta.isNotEmpty, isTrue);
    });

    test('equal ends make equal deltas', () {
      const a = RegisterDelta<String>(previous: 'a', current: 'b');
      const b = RegisterDelta<String>(previous: 'a', current: 'b');

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('the two ends are told apart', () {
      const a = RegisterDelta<String>(previous: 'a', current: 'b');
      const b = RegisterDelta<String>(previous: 'b', current: 'a');

      expect(a, isNot(b));
    });

    test('the description names both ends', () {
      const delta = RegisterDelta<String>(previous: 'a', current: 'b');

      expect(delta.toString(), 'RegisterDelta(a -> b)');
    });
  });
}
