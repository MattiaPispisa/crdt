import 'dart:convert';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/common/common/common.dart';
import 'package:crdt_socket_sync/src/plugins/common/common.dart';
import 'package:crdt_socket_sync/src/relay/common/common.dart';
import 'package:test/test.dart';

void main() {
  group('RelayMessage', () {
    const documentId = 'room-1';

    /// Encodes with [Message.toJson] and decodes with [RelayMessage.fromJson],
    /// asserting the round-tripped JSON is identical.
    T roundTrip<T extends Message>(T message) {
      final json =
          jsonDecode(jsonEncode(message.toJson())) as Map<String, dynamic>;
      final decoded = RelayMessage.fromJson(json);
      expect(decoded, isNotNull);
      expect(decoded, isA<T>());
      expect(decoded!.toJson(), message.toJson());
      return decoded as T;
    }

    test('hello round-trips', () {
      final author = PeerId.generate();
      final decoded = roundTrip(
        RelayHelloMessage(documentId: documentId, author: author),
      );
      expect(decoded.author, author);
    });

    test('welcome round-trips', () {
      final decoded = roundTrip(
        const RelayWelcomeMessage(
          documentId: documentId,
          sessionId: 'session-1',
          snapshot: 'c25hcA==',
          changes: ['YQ==', 'Yg=='],
          seq: 12,
          logLength: 2,
          compact: true,
        ),
      );
      expect(decoded.sessionId, 'session-1');
      expect(decoded.snapshot, 'c25hcA==');
      expect(decoded.changes, ['YQ==', 'Yg==']);
      expect(decoded.seq, 12);
      expect(decoded.logLength, 2);
      expect(decoded.compact, isTrue);
    });

    test('welcome round-trips without snapshot', () {
      final decoded = roundTrip(
        const RelayWelcomeMessage(
          documentId: documentId,
          sessionId: 'session-1',
          changes: [],
          seq: 0,
          logLength: 0,
          compact: false,
        ),
      );
      expect(decoded.snapshot, isNull);
      expect(decoded.changes, isEmpty);
    });

    test('push round-trips', () {
      final decoded = roundTrip(
        const RelayPushMessage(documentId: documentId, changes: ['YQ==']),
      );
      expect(decoded.changes, ['YQ==']);
    });

    test('ack round-trips', () {
      final decoded = roundTrip(
        const RelayAckMessage(
          documentId: documentId,
          seq: 42,
          count: 3,
          logLength: 42,
          compact: false,
        ),
      );
      expect(decoded.seq, 42);
      expect(decoded.count, 3);
    });

    test('changes round-trips', () {
      final decoded = roundTrip(
        const RelayChangesMessage(
          documentId: documentId,
          changes: ['YQ==', 'Yg=='],
          seq: 9,
          from: 'session-2',
        ),
      );
      expect(decoded.changes, hasLength(2));
      expect(decoded.seq, 9);
      expect(decoded.from, 'session-2');
    });

    test('snapshot upload round-trips', () {
      final decoded = roundTrip(
        const RelaySnapshotUploadMessage(
          documentId: documentId,
          snapshot: 'c25hcA==',
          upToSeq: 200,
        ),
      );
      expect(decoded.snapshot, 'c25hcA==');
      expect(decoded.upToSeq, 200);
    });

    test('state request round-trips', () {
      roundTrip(const RelayStateRequestMessage(documentId: documentId));
    });

    test('push preserves crdt_lf change bytes exactly', () {
      final document = CRDTDocument(peerId: PeerId.generate());
      final handler = CRDTFugueTextHandler(document, 'content')
        ..insert(0, 'hello');
      expect(handler.value, 'hello');

      final blobs = document
          .exportChanges()
          .map((change) => base64Encode(change.toBytes()))
          .toList();
      final decoded = roundTrip(
        RelayPushMessage(documentId: documentId, changes: blobs),
      );

      final replica = CRDTDocument(peerId: PeerId.generate());
      final replicaHandler = CRDTFugueTextHandler(replica, 'content');
      replica.importChanges(
        decoded.changes
            .map((blob) => Change.fromBytes(base64Decode(blob)))
            .toList(),
      );
      expect(replicaHandler.value, 'hello');
    });

    test('fromJson returns null outside the relay range', () {
      Map<String, dynamic> frame(int type) => {
            'type': type,
            'documentId': documentId,
          };

      for (final type in [0, 8, 19, 27, 39, 100, 102]) {
        expect(RelayMessage.fromJson(frame(type)), isNull);
      }
    });

    test('relay type codes do not collide with core or plugin codes', () {
      final coreCodes = MessageType.values.map((type) => type.value).toSet();
      final relayCodes =
          RelayMessageType.values.map((type) => type.value).toSet();

      expect(coreCodes.intersection(relayCodes), isEmpty);
      expect(relayCodes.every((code) => code >= 20 && code <= 39), isTrue);
      // Plugin codes start at 100.
      expect(relayCodes.every((code) => code < 100), isTrue);
    });

    test('getTypeOrNull reads the type of an encoded relay frame', () {
      final codec = JsonMessageCodec<Message>(
        toJson: (message) => message.toJson(),
        fromJson: (json) =>
            RelayMessage.fromJson(json) ?? Message.fromJson(json),
      );

      final data = codec.encode(
        const RelayStateRequestMessage(documentId: documentId),
      );
      expect(
        Message.getTypeOrNull(data!),
        RelayMessageType.relayStateRequest.value,
      );
    });

    test('a plugin-aware codec decodes relay and core frames', () {
      final codec = PluginAwareMessageCodec.fromPlugins(
        plugins: const [],
        defaultCodec: JsonMessageCodec<Message>(
          toJson: (message) => message.toJson(),
          fromJson: (json) =>
              RelayMessage.fromJson(json) ?? Message.fromJson(json),
        ),
      );

      final relayFrame = codec.encode(
        const RelayPushMessage(documentId: documentId, changes: ['YQ==']),
      );
      expect(codec.decode(relayFrame!), isA<RelayPushMessage>());

      final coreFrame = codec.encode(
        Message.ping(documentId: documentId, timestamp: 7),
      );
      expect(codec.decode(coreFrame!), isA<PingMessage>());
    });
  });
}
