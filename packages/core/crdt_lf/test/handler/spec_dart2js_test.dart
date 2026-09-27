// A file of its own on purpose, next to spec_test.dart. dart2js (Dart 3.13)
// emitted the builder call of `HandlerSpec.create` twice, but only in a
// program that builds handlers from a single spec. Keep this file to one spec,
// or it stops reproducing. Run it with `dart test -p chrome`.
import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
  test('BaseCRDTDocument.handler builds one handler under dart2js', () {
    final doc = CRDTDocument(peerId: PeerId.generate());

    final first = doc.handler(CRDTFugueTextHandler.spec, 'text');
    final second = doc.handler(CRDTFugueTextHandler.spec, 'text');

    expect(identical(first, second), isTrue);
  });
}
