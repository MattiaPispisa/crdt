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
}
