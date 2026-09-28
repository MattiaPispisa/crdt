import 'package:test/test.dart';

/// `host_test.dart` is `@TestOn('vm')` (Hive needs a directory), and a Chrome
/// run with nothing in it fails.
void main() {
  test('no-op', () {
    expect(() {}, returnsNormally);
  });
}
