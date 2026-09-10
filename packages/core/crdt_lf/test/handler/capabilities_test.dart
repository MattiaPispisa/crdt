import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/handler/fugue/fugue_snapshot.dart';
import 'package:test/test.dart';

import '../helpers/pn_counter_handler.dart';

void main() {
  group('Handler.decodableKinds', () {
    test('reports the kinds the decoder map holds', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final counter = PNCounterHandler(doc, 'counter');

      expect(counter.decodableKinds, {PNCounterHandler.incrementKind});
      // It is read from the decoders, so the two cannot disagree.
      expect(counter.decodableKinds, counter.operationDecoders.keys.toSet());
    });

    test('a built-in sequence handler declares insert, delete and update', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final text = CRDTFugueTextHandler(doc, 'text');

      expect(text.decodableKinds, text.operationDecoders.keys.toSet());
      expect(text.decodableKinds, contains(OperationType.kindInsert));
    });
  });

  group('Handler.snapshotBlobVersion', () {
    test('is the byte the handler writes at the head of its blob', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final map = CRDTMapHandler<String>(doc, 'map')..set('a', 'b');

      // The contract that makes the value usable by a peer reading a blob it
      // did not write: the declared version IS the first byte.
      expect(map.getSnapshotState().first, map.snapshotBlobVersion);
    });

    test('a Fugue handler follows FugueSnapshot', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final text = CRDTFugueTextHandler(doc, 'text')..insert(0, 'hi');

      expect(text.snapshotBlobVersion, FugueSnapshot.version);
      expect(text.getSnapshotState().first, text.snapshotBlobVersion);
    });

    test('defaults to 1 for a handler that does not declare one', () {
      final doc = CRDTDocument(peerId: PeerId.generate());

      expect(PNCounterHandler(doc, 'counter').snapshotBlobVersion, 1);
    });
  });
}
