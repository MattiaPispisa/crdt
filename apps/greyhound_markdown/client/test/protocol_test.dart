import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greyhound_markdown_client/src/model/protocol.dart';

void main() {
  group('ProtocolMessage', () {
    ProtocolMessage roundTrip(ProtocolMessage message) =>
        ProtocolMessage.decode(message.encode())!;

    test('welcome round-trips including null snapshot', () {
      final decoded =
          roundTrip(
                WelcomeMessage(
                  snapshot: null,
                  changes: [
                    Uint8List.fromList([1, 2, 3]),
                  ],
                  seq: 7,
                  logLen: 1,
                  peers: {
                    'peer-a': {'name': 'Ann'},
                  },
                  compact: true,
                ),
              )
              as WelcomeMessage;
      expect(decoded.snapshot, isNull);
      expect(decoded.changes.single, [1, 2, 3]);
      expect(decoded.seq, 7);
      expect(decoded.logLen, 1);
      expect(decoded.peers['peer-a'], {'name': 'Ann'});
      expect(decoded.compact, isTrue);
    });

    test('push preserves crdt_lf change bytes exactly', () {
      // ASCII only: non-BMP characters are corrupted by a known
      // export/import bug in the fugue text handler.
      final doc = CRDTDocument();
      CRDTFugueTextHandler(doc, 'content').insert(0, 'hello');
      final blobs = doc.exportChanges().map((c) => c.toBytes()).toList();

      final decoded = roundTrip(PushMessage(changes: blobs)) as PushMessage;
      expect(decoded.changes, blobs);

      final replica = CRDTDocument();
      final text = CRDTFugueTextHandler(replica, 'content');
      for (final blob in decoded.changes) {
        replica.importChanges([Change.fromBytes(blob)]);
      }
      expect(text.value, 'hello');
    });

    test('ack, change, snapshot, awareness, peer_left round-trip', () {
      final ack =
          roundTrip(const AckMessage(seq: 3, logLen: 2, compact: false))
              as AckMessage;
      expect((ack.seq, ack.logLen, ack.compact), (3, 2, false));

      final change =
          roundTrip(
                ChangeMessage(
                  from: 'peer-b',
                  changes: [
                    Uint8List.fromList([9, 8]),
                  ],
                ),
              )
              as ChangeMessage;
      expect(change.from, 'peer-b');
      expect(change.changes.single, [9, 8]);

      final snapshot =
          roundTrip(
                SnapshotMessage(
                  snapshot: Uint8List.fromList([4, 5, 6]),
                  upto: 12,
                ),
              )
              as SnapshotMessage;
      expect(snapshot.snapshot, [4, 5, 6]);
      expect(snapshot.upto, 12);

      final awareness =
          roundTrip(
                const AwarenessMessage(
                  from: 'peer-c',
                  state: {'name': 'Cy', 'cursor': null},
                ),
              )
              as AwarenessMessage;
      expect(awareness.from, 'peer-c');
      expect(awareness.state, {'name': 'Cy', 'cursor': null});

      final left =
          roundTrip(const PeerLeftMessage(clientId: 'peer-d'))
              as PeerLeftMessage;
      expect(left.clientId, 'peer-d');
    });

    test('decode returns null for unknown types', () {
      expect(ProtocolMessage.decode('{"type":"nope"}'), isNull);
    });
  });
}
