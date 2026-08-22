import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/common/common/common.dart';
import 'package:crdt_socket_sync/src/common/server/client_session.dart';
import 'package:crdt_socket_sync/src/common/server/client_session_event.dart';
import 'package:crdt_socket_sync/src/plugins/server.dart';
import 'package:crdt_socket_sync/src/relay/common/common.dart';
import 'package:crdt_socket_sync/src/relay/server/compaction.dart';
import 'package:crdt_socket_sync/src/relay/server/in_memory_relay_store.dart';
import 'package:crdt_socket_sync/src/relay/server/relay_client_session.dart';
import 'package:crdt_socket_sync/src/relay/server/relay_session_event.dart';
import 'package:crdt_socket_sync/src/relay/server/store.dart';
import 'package:crdt_socket_sync/src/server_client/common/common.dart';
import 'package:test/test.dart';

/// A controllable bidirectional connection: the test pushes inbound frames on
/// [inbound] and inspects captured outbound frames in [sent].
class _FakeConnection implements TransportConnection {
  final _incoming = StreamController<List<int>>();
  final List<List<int>> sent = [];
  bool _connected = true;

  void inbound(List<int> data) => _incoming.add(data);

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  @override
  Future<void> send(List<int> data) async => sent.add(data);

  @override
  Future<void> close() async {
    _connected = false;
    if (!_incoming.isClosed) {
      await _incoming.close();
    }
  }

  @override
  bool get isConnected => _connected;
}

/// A codec that never encodes nor decodes anything.
class _NullCodec implements MessageCodec<Message> {
  @override
  List<int>? encode(Message message) => null;

  @override
  Message? decode(List<int> data) => null;
}

/// Records the plugin hooks fired by the session.
class _RecordingPlugin extends ServerSyncPlugin {
  final List<String> calls = [];

  @override
  String get name => 'recording';

  @override
  MessageCodec<Message> get messageCodec => _NullCodec();

  @override
  void onNewSession(ClientSession session) => calls.add('newSession');

  @override
  void onMessage(ClientSession session, Message message) =>
      calls.add('message:${message.type.value}');

  @override
  void onDocumentRegistered(ClientSession session, String documentId) =>
      calls.add('registered:$documentId');

  @override
  void onSessionClosed(ClientSession session) => calls.add('closed');

  @override
  void dispose() {}
}

void main() {
  const documentId = 'room-1';

  final codec = JsonMessageCodec<Message>(
    toJson: (m) => m.toJson(),
    fromJson: (json) => RelayMessage.fromJson(json) ?? Message.fromJson(json),
  );

  late InMemoryRelayStore store;
  late RelayCompactionCoordinator compaction;
  late _FakeConnection connection;
  late RelayClientSession session;
  late List<SessionEvent> events;

  RelayClientSession createSession({List<ServerSyncPlugin>? plugins}) {
    return RelayClientSession(
      id: 'session-1',
      connection: connection,
      store: store,
      compaction: compaction,
      plugins: plugins ?? const [],
    );
  }

  setUp(() {
    store = InMemoryRelayStore();
    compaction = RelayCompactionCoordinator(logCompactThreshold: 5);
    connection = _FakeConnection();
    session = createSession();
    events = [];
    session.events.listen(events.add);
  });

  tearDown(() => session.dispose());

  List<Message> decodeSent() =>
      connection.sent.map(codec.decode).whereType<Message>().toList();

  Future<void> pump() => Future<void>.delayed(Duration.zero);

  Future<void> hello() async {
    connection.inbound(
      codec.encode(
        RelayHelloMessage(
          documentId: documentId,
          author: PeerId.generate(),
        ),
      )!,
    );
    await pump();
  }

  group('RelayClientSession join', () {
    test('hello on an empty room answers an empty welcome', () async {
      await hello();

      final welcome = decodeSent().whereType<RelayWelcomeMessage>().single;
      expect(welcome.sessionId, 'session-1');
      expect(welcome.snapshot, isNull);
      expect(welcome.changes, isEmpty);
      expect(welcome.seq, 0);
      expect(welcome.logLength, 0);
      expect(welcome.compact, isFalse);

      expect(session.isSubscribedTo(documentId), isTrue);
      expect(
        events.whereType<RelaySessionEventJoined>().single.documentId,
        documentId,
      );
    });

    test('hello on a room with state serves snapshot plus newer log', () async {
      await store.append(documentId, ['a', 'b', 'c']);
      await store.saveSnapshot(
        documentId,
        const RelaySnapshotRecord(blob: 'snap', upToSeq: 2),
      );

      await hello();

      final welcome = decodeSent().whereType<RelayWelcomeMessage>().single;
      expect(welcome.snapshot, 'snap');
      expect(welcome.changes, ['c']);
      expect(welcome.seq, 3);
      expect(welcome.logLength, 1);
    });

    test('hello fires plugin hooks in order', () async {
      final plugin = _RecordingPlugin();
      session.dispose();
      connection = _FakeConnection();
      session = createSession(plugins: [plugin]);

      await hello();

      expect(
        plugin.calls,
        [
          'newSession',
          'message:${RelayMessageType.relayHello.value}',
          'registered:$documentId',
        ],
      );
    });
  });

  group('RelayClientSession push', () {
    test('persists blobs, acks and emits the pushed event', () async {
      await hello();

      connection.inbound(
        codec.encode(
          const RelayPushMessage(documentId: documentId, changes: ['a', 'b']),
        )!,
      );
      await pump();

      final ack = decodeSent().whereType<RelayAckMessage>().single;
      expect(ack.seq, 2);
      expect(ack.count, 2);
      expect(ack.logLength, 2);
      expect(ack.compact, isFalse);

      final log = await store.readLog(documentId);
      expect(log.map((e) => e.blob), ['a', 'b']);

      final pushed = events.whereType<RelaySessionEventChangesPushed>().single;
      expect(pushed.changes, ['a', 'b']);
      expect(pushed.seq, 2);
    });

    test('asks for compaction past the log threshold', () async {
      await hello();

      connection.inbound(
        codec.encode(
          const RelayPushMessage(
            documentId: documentId,
            changes: ['a', 'b', 'c', 'd', 'e', 'f'],
          ),
        )!,
      );
      await pump();

      final ack = decodeSent().whereType<RelayAckMessage>().single;
      expect(ack.logLength, 6);
      expect(ack.compact, isTrue);
    });

    test('push without a join is rejected', () async {
      connection.inbound(
        codec.encode(
          const RelayPushMessage(documentId: documentId, changes: ['a']),
        )!,
      );
      await pump();

      expect(decodeSent(), isEmpty);
      expect(await store.logLength(documentId), 0);
      expect(
        events.where((e) => e.type == SessionEventType.error),
        hasLength(1),
      );
    });

    test('an empty push is ignored', () async {
      await hello();

      connection.inbound(
        codec.encode(
          const RelayPushMessage(documentId: documentId, changes: []),
        )!,
      );
      await pump();

      expect(decodeSent().whereType<RelayAckMessage>(), isEmpty);
      expect(events.whereType<RelaySessionEventChangesPushed>(), isEmpty);
    });
  });

  group('RelayClientSession snapshot upload', () {
    test('persists the snapshot, truncates the log and resets the limiter',
        () async {
      await hello();
      connection.inbound(
        codec.encode(
          const RelayPushMessage(
            documentId: documentId,
            changes: ['a', 'b', 'c', 'd', 'e', 'f'],
          ),
        )!,
      );
      await pump();
      // The threshold crossing above consumed the rate limiter.
      expect(
        decodeSent().whereType<RelayAckMessage>().single.compact,
        isTrue,
      );

      connection.inbound(
        codec.encode(
          const RelaySnapshotUploadMessage(
            documentId: documentId,
            snapshot: 'snap',
            upToSeq: 6,
          ),
        )!,
      );
      await pump();

      final snapshot = await store.getSnapshot(documentId);
      expect(snapshot!.blob, 'snap');
      expect(await store.logLength(documentId), 0);
      expect(
        events.whereType<RelaySessionEventSnapshotUploaded>().single.upToSeq,
        6,
      );

      // The limiter was reset: the next threshold crossing asks again
      // without waiting for the retry interval.
      connection.inbound(
        codec.encode(
          const RelayPushMessage(
            documentId: documentId,
            changes: ['g', 'h', 'i', 'j', 'k', 'l'],
          ),
        )!,
      );
      await pump();
      expect(
        decodeSent().whereType<RelayAckMessage>().last.compact,
        isTrue,
      );
    });
  });

  group('RelayClientSession state request', () {
    test('answers with the current room state', () async {
      await hello();
      connection.inbound(
        codec.encode(
          const RelayPushMessage(documentId: documentId, changes: ['a']),
        )!,
      );
      await pump();

      connection.inbound(
        codec.encode(
          const RelayStateRequestMessage(documentId: documentId),
        )!,
      );
      await pump();

      final welcomes = decodeSent().whereType<RelayWelcomeMessage>().toList();
      expect(welcomes, hasLength(2));
      expect(welcomes.last.changes, ['a']);
      expect(welcomes.last.seq, 1);
    });
  });

  group('RelayClientSession protocol guards', () {
    test('CRDT sync protocol messages are answered with an error', () async {
      connection.inbound(
        codec.encode(
          SyncMessage.documentStatusRequest(
            documentId: documentId,
            versionVector: null,
          ),
        )!,
      );
      await pump();

      final error = decodeSent().whereType<ErrorMessage>().single;
      expect(error.code, Protocol.errorInvalidMessage);
    });

    test('ping is answered with pong', () async {
      connection.inbound(
        codec.encode(Message.ping(documentId: documentId, timestamp: 7))!,
      );
      await pump();

      final pong = decodeSent().whereType<PongMessage>().single;
      expect(pong.originalTimestamp, 7);
    });
  });
}
