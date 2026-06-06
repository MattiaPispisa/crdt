import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
  group('Operation bytes', () {
    test('CRDTTextHandler operation bytes roundtrip', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final text = CRDTTextHandler(doc, 'text')
        ..insert(0, 'Hello')
        ..insert(5, ' World')
        ..delete(5, 1)
        ..update(0, 'h');

      final changes = doc.exportChanges().sorted();

      // Decode operations from bytes and ensure payload is well-formed.
      for (final change in changes) {
        final op = text.operationFactory(change.payloadBytes());
        expect(op, isNotNull);

        final payload = op!.toPayload();
        expect(payload['id'], equals('text'));
        expect(payload['type'], isA<String>());
      }
    });
  });
}
