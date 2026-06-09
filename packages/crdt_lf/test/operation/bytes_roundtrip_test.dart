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

    test('CRDTListHandler operation bytes roundtrip exercises toPayload', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final list = CRDTListHandler<String>(doc, 'list')
        ..insert(0, 'a')
        ..insert(1, 'b')
        ..update(0, 'A')
        ..delete(1, 1);

      final changes = doc.exportChanges().sorted();
      expect(changes, isNotEmpty);

      for (final change in changes) {
        final op = list.operationFactory(change.payloadBytes());
        expect(op, isNotNull);
        final payload = op!.toPayload();
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

      final changes = doc.exportChanges().sorted();
      expect(changes, isNotEmpty);

      for (final change in changes) {
        final op = map.operationFactory(change.payloadBytes());
        expect(op, isNotNull);
        final payload = op!.toPayload();
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

      final changes = doc.exportChanges().sorted();
      expect(changes, isNotEmpty);

      for (final change in changes) {
        final op = set.operationFactory(change.payloadBytes());
        expect(op, isNotNull);
        final payload = op!.toPayload();
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

      final changes = doc.exportChanges().sorted();
      expect(changes, isNotEmpty);

      for (final change in changes) {
        final op = orMap.operationFactory(change.payloadBytes());
        expect(op, isNotNull);
        final payload = op!.toPayload();
        expect(payload['id'], equals('omap'));
        expect(payload['type'], isA<String>());
        expect(payload.containsKey('key'), isTrue);
      }
    });
  });
}
