@TestOn('vm')
library;

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/relay_server.dart';
import 'package:test/test.dart';

import '../../utils/fake_connection.dart';

/// The relay host, driven entirely through `acceptConnection`.
///
/// No `HttpServer` and no upgrade: this is the relay protocol as an embedder
/// (Dart Frog, shelf, a worker) sees it.
void main() {
  group('RelaySessionHost', () {
    const roomId = 'room-1';

    late InMemoryRelayStore store;
    late RelaySessionHost host;
    late JsonMessageCodec<Message> codec;
    late List<ServerEvent> events;

    setUp(() {
      store = InMemoryRelayStore();
      host = RelaySessionHost(store: store);
      codec = JsonMessageCodec<Message>(
        toJson: (message) => message.toJson(),
        fromJson: (json) =>
            RelayMessage.fromJson(json) ?? Message.fromJson(json),
      );
      events = [];
      host.serverEvents.listen(events.add);
    });

    tearDown(() => host.dispose());

    List<Message> decodeAll(FakeTransportConnection connection) {
      return connection.sent.map(codec.decode).nonNulls.toList();
    }

    Future<FakeTransportConnection> join(String documentId) async {
      final connection = FakeTransportConnection();
      host.acceptConnection(connection);
      await Future<void>.delayed(Duration.zero);

      connection.receive(
        codec.encode(
          RelayHelloMessage(
            documentId: documentId,
            author: PeerId.generate(),
          ),
        )!,
      );
      await Future<void>.delayed(Duration.zero);
      return connection;
    }

    test('answers a hello with a welcome carrying the session id', () async {
      await host.start();

      final connection = await join(roomId);

      final welcome = decodeAll(connection).single as RelayWelcomeMessage;
      expect(welcome.documentId, roomId);
      expect(welcome.sessionId, isNotEmpty);
      expect(welcome.changes, isEmpty);
      expect(welcome.seq, 0);
      expect(
        events.map((e) => e.type),
        containsAllInOrder([
          ServerEventType.clientConnected,
          ServerEventType.clientHandshake,
        ]),
      );
    });

    test('acks a push and rebroadcasts it to the rest of the room', () async {
      await host.start();

      final author = await join(roomId);
      final listener = await join(roomId);

      author.receive(
        codec.encode(
          const RelayPushMessage(documentId: roomId, changes: ['blob-a']),
        )!,
      );
      await Future<void>.delayed(Duration.zero);

      final ack = decodeAll(author).whereType<RelayAckMessage>().single;
      expect(ack.seq, 1);
      expect(ack.count, 1);

      final relayed =
          decodeAll(listener).whereType<RelayChangesMessage>().single;
      expect(relayed.changes, ['blob-a']);
      expect(relayed.seq, 1);

      // The pusher does not get its own blobs back.
      expect(decodeAll(author).whereType<RelayChangesMessage>(), isEmpty);

      // And the blob is in the log, which is what a late joiner will read.
      expect(await store.logLength(roomId), 1);
    });

    test('serves the stored log to a client that joins later', () async {
      await host.start();

      final first = await join(roomId);
      first.receive(
        codec.encode(
          const RelayPushMessage(documentId: roomId, changes: ['blob-a']),
        )!,
      );
      await Future<void>.delayed(Duration.zero);

      final late = await join(roomId);

      final welcome = decodeAll(late).whereType<RelayWelcomeMessage>().single;
      expect(welcome.changes, ['blob-a']);
      expect(welcome.seq, 1);
    });

    test('a client of another room does not see the blobs', () async {
      await host.start();

      final author = await join(roomId);
      final outsider = await join('room-2');

      author.receive(
        codec.encode(
          const RelayPushMessage(documentId: roomId, changes: ['blob-a']),
        )!,
      );
      await Future<void>.delayed(Duration.zero);

      expect(decodeAll(outsider).whereType<RelayChangesMessage>(), isEmpty);
    });

    test('stores an uploaded snapshot and truncates the log', () async {
      await host.start();

      final connection = await join(roomId);
      connection.receive(
        codec.encode(
          const RelayPushMessage(documentId: roomId, changes: ['blob-a']),
        )!,
      );
      await Future<void>.delayed(Duration.zero);

      connection.receive(
        codec.encode(
          const RelaySnapshotUploadMessage(
            documentId: roomId,
            snapshot: 'snap',
            upToSeq: 1,
          ),
        )!,
      );
      await Future<void>.delayed(Duration.zero);

      expect((await store.getSnapshot(roomId))?.blob, 'snap');
      expect(await store.logLength(roomId), 0);
      expect(
        events.where((e) => e.type == ServerEventType.snapshotCreated),
        hasLength(1),
      );
    });

    test('exposes its store and compaction coordinator', () {
      final coordinator = RelayCompactionCoordinator();
      final configured = RelaySessionHost(
        store: store,
        compaction: coordinator,
      );

      expect(configured.store, same(store));
      expect(configured.compaction, same(coordinator));

      return configured.dispose();
    });
  });
}
