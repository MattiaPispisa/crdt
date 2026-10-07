import 'package:test/test.dart';

/// Every other test here is `@TestOn('vm')`: this package serves HTTP, which
/// a browser cannot do. `melos run test_chrome` still runs `dart test -p
/// chrome` over the package, and a run with nothing in it fails — so this
/// keeps the browser run honest without pretending the rest could work there.
void main() {
  test('no-op', () {
    expect(() {}, returnsNormally);
  });
}
