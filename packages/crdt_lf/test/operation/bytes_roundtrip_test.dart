import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

/// `[varint 15]'CRDTTextHandler'[varint 4]'text'` — the envelope prefix, the
/// part the zero-decode routing compares byte for byte.
const _textPrefix = <int>[
  15, 67, 82, 68, 84, 84, 101, 120, 116, 72, 97, 110, 100, 108, 101, 114, //
  4, 116, 101, 120, 116,
];

void main() {
  group('Operation bytes', () {
    // Pinned on purpose, and captured from the encoder before it knew about
    // stamps. A handler that does not ask to be stamped has to keep writing
    // exactly these bytes: the stamp flag is bit 7 of the kind byte, so a
    // build that sets it by mistake would be read wrong by every other peer,
    // with no error anywhere. Delete this test and that breakage goes quiet.
    test('an unstamped operation keeps the envelope it had before stamps', () {
      final doc = CRDTDocument(
        peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
      );
      CRDTTextHandler(doc, 'text')
        ..insert(0, 'Hello')
        ..delete(1, 2)
        ..update(0, 'h');

      final payloads = doc
          .exportChanges()
          .sorted()
          .map((change) => change.payloadBytes().toList())
          .toList();

      expect(payloads, hasLength(3));
      // kind 0, index 0, length 5, 'Hello'
      expect(
        payloads[0],
        equals([..._textPrefix, 0, 0, 5, 72, 101, 108, 108, 111]),
      );
      // kind 1, index 1, count 2
      expect(payloads[1], equals([..._textPrefix, 1, 1, 2]));
      // kind 2, index 0, length 1, 'h'
      expect(payloads[2], equals([..._textPrefix, 2, 0, 1, 104]));
    });

    test('CRDTTextHandler operation bytes roundtrip', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final text = CRDTTextHandler(doc, 'text')
        ..insert(0, 'Hello')
        ..insert(5, ' World')
        ..delete(5, 1)
        ..update(0, 'h');

      final operations = text.operations();
      expect(operations, isNotEmpty);

      for (final operation in operations) {
        final payload = operation.toPayload();
        expect(payload['id'], equals('text'));
        expect(payload['type'], isA<String>());
      }
    });

    test('CRDTListHandler operation bytes roundtrip exercises toPayload', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final list = CRDTListHandler<String>(doc, 'list')
        ..insert(0, 'a')
        ..insert(1, 'b')
        ..update(0, 'A')
        ..delete(1, 1);

      final operations = list.operations();
      expect(operations, isNotEmpty);

      for (final operation in operations) {
        final payload = operation.toPayload();
        expect(payload['id'], equals('list'));
        expect(payload['type'], isA<String>());
        expect(payload.containsKey('index'), isTrue);
      }
    });

    test('CRDTMapHandler operation bytes roundtrip exercises toPayload', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final map = CRDTMapHandler<String>(doc, 'map')
        ..set('k1', 'v1')
        ..set('k2', 'v2')
        ..update('k1', 'V1')
        ..delete('k2');

      final operations = map.operations();
      expect(operations, isNotEmpty);

      for (final operation in operations) {
        final payload = operation.toPayload();
        expect(payload['id'], equals('map'));
        expect(payload['type'], isA<String>());
        expect(payload.containsKey('key'), isTrue);
      }
    });

    test('CRDTORSetHandler operation bytes roundtrip exercises toPayload', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final set = CRDTORSetHandler<String>(doc, 'oset')
        ..add('x')
        ..add('y')
        ..remove('x');

      final operations = set.operations();
      expect(operations, isNotEmpty);

      for (final operation in operations) {
        final payload = operation.toPayload();
        expect(payload['id'], equals('oset'));
        expect(payload['type'], isA<String>());
        expect(payload.containsKey('value'), isTrue);
      }
    });

    test('CRDTORMapHandler operation bytes roundtrip exercises toPayload', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final orMap = CRDTORMapHandler<String, int>(doc, 'omap')
        ..put('k1', 1)
        ..put('k2', 2)
        ..remove('k1');

      final operations = orMap.operations();
      expect(operations, isNotEmpty);

      for (final operation in operations) {
        final payload = operation.toPayload();
        expect(payload['id'], equals('omap'));
        expect(payload['type'], isA<String>());
        expect(payload.containsKey('key'), isTrue);
      }
    });
  });
}
