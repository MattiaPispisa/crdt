import 'dart:async';
import 'dart:convert';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/web_socket_relay_client.dart';
import 'package:test/test.dart';

/// A fully controllable in-memory [Transport] acting as a minimal relay:
/// answers hello/state requests with a welcome, acks pushes and answers
/// pings, recording everything the client sends.
class _FakeRelayTransport implements Transport {
  _FakeRelayTransport({
    required this.documentId,
    this.initialChanges = const [],
    this.compactOnWelcome = false,
  });

  final String documentId;
  final List<String> initialChanges;
  final bool compactOnWelcome;

  final List<Message> received = [];

  final _incoming = StreamController<List<int>>.broadcast();
  final _codec = JsonMessageCodec<Message>(
    toJson: (m) => m.toJson(),
    fromJson: (json) => RelayMessage.fromJson(json) ?? Message.fromJson(json),
  );

  int _seq = 0;
  bool _closed = false;

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  @override
  bool get isConnected => !_closed;

  @override
  Future<void> send(List<int> data) async {
    final message = _codec.decode(data);
    if (message == null) return;
    received.add(message);

    if (message is RelayHelloMessage || message is RelayStateRequestMessage) {
      _seq = initialChanges.length;
      push(
        RelayWelcomeMessage(
          documentId: documentId,
          sessionId: 'session-1',
          changes: initialChanges,
          seq: _seq,
          logLength: initialChanges.length,
          compact: compactOnWelcome,
        ),
      );
    } else if (message is RelayPushMessage) {
      _seq += message.changes.length;
      push(
        RelayAckMessage(
          documentId: documentId,
          seq: _seq,
          count: message.changes.length,
          logLength: _seq,
          compact: false,
        ),
      );
    } else if (message is PingMessage) {
      push(
        PongMessage(
          documentId: documentId,
          originalTimestamp: message.timestamp,
          responseTimestamp: message.timestamp,
        ),
      );
    }
  }

  void push(Message message) {
    if (_closed || _incoming.isClosed) return;
    final data = _codec.encode(message);
    if (data != null) _incoming.add(data);
  }

  void pushRaw(List<int> data) {
    if (_closed || _incoming.isClosed) return;
    _incoming.add(data);
  }

  @override
  Future<void> close() async {
    _closed = true;
  }
}

/// Records the client plugin callbacks.
class _RecordingPlugin extends ClientSyncPlugin {
  final List<String> calls = [];

  @override
  String get name => 'recording';

  @override
  MessageCodec<Message> get messageCodec => _NullCodec();

  @override
  void onConnected() => calls.add('connected:${client.sessionId}');

  @override
  void onDisconnected() => calls.add('disconnected');

  @override
  void onMessage(Message message) => calls.add('message:${message.type.value}');

  @override
  void dispose() {}
}

class _NullCodec implements MessageCodec<Message> {
  @override
  List<int>? encode(Message message) => null;

  @override
  Message? decode(List<int> data) => null;
}

void main() {
  group('WebSocketRelayClient', () {
    const documentId = 'room-1';

    late CRDTDocument document;
    late CRDTFugueTextHandler handler;

    setUp(() {
      document = CRDTDocument(
        peerId: PeerId.generate(),
        documentId: documentId,
      );
      handler = CRDTFugueTextHandler(document, 'content');
    });

    WebSocketRelayClient buildClient(
      _FakeRelayTransport transport, {
      List<ClientSyncPlugin>? plugins,
    }) {
      final client = WebSocketRelayClient.test(
        url: 'ws://localhost:0',
        document: document,
        author: document.peerId,
        transportFactory: () => transport,
        plugins: plugins,
      );
      addTearDown(client.dispose);
      return client;
    }

    Future<void> pump() => Future<void>.delayed(Duration.zero);

    /// Blobs of every change of a fresh document containing [text].
    List<String> blobsOfText(String text) {
      final peer = CRDTDocument(peerId: PeerId.generate());
      CRDTFugueTextHandler(peer, 'content').insert(0, text);
      return peer
          .exportChanges()
          .map((change) => base64Encode(change.toBytes()))
          .toList();
    }

    test('connect joins the room and imports the served state', () async {
      final transport = _FakeRelayTransport(
        documentId: documentId,
        initialChanges: blobsOfText('hello'),
      );
      final client = buildClient(transport);

      final statuses = <ConnectionStatus>[];
      client.connectionStatus.listen(statuses.add);

      expect(await client.connect(), isTrue);
      await pump();

      expect(client.sessionId, 'session-1');
      expect(client.connectionStatusValue, ConnectionStatus.connected);
      expect(statuses, contains(ConnectionStatus.connecting));
      expect(handler.value, 'hello');
      expect(client.lastKnownSeq, transport.initialChanges.length);
    });

    test('plugins connect after the session id is assigned', () async {
      final plugin = _RecordingPlugin();
      final transport = _FakeRelayTransport(documentId: documentId);
      final client = buildClient(transport, plugins: [plugin]);

      await client.connect();

      // Awareness relies on this ordering: `onConnected` publishes the
      // local state keyed by the session id.
      expect(plugin.calls, contains('connected:session-1'));
    });

    test('local edits are pushed and acked', () async {
      final transport = _FakeRelayTransport(documentId: documentId);
      final client = buildClient(transport);
      await client.connect();

      handler.insert(0, 'ab');
      await pump();
      await pump();

      expect(transport.received.whereType<RelayPushMessage>(), isNotEmpty);
      expect(client.pendingChangesCount, 0);
      expect(client.lastKnownSeq, greaterThan(0));
    });

    test('rebroadcast changes of other clients are imported', () async {
      final transport = _FakeRelayTransport(documentId: documentId);
      final client = buildClient(transport);
      await client.connect();

      final remote = blobsOfText('hi');
      transport.push(
        RelayChangesMessage(
          documentId: documentId,
          changes: remote,
          seq: remote.length,
          from: 'session-2',
        ),
      );
      await pump();

      expect(handler.value, 'hi');
    });

    test('a compact welcome answers with a snapshot upload', () async {
      final transport = _FakeRelayTransport(
        documentId: documentId,
        initialChanges: blobsOfText('hello'),
        compactOnWelcome: true,
      );
      final client = buildClient(transport);
      await client.connect();
      await pump();

      final upload =
          transport.received.whereType<RelaySnapshotUploadMessage>().single;
      expect(upload.upToSeq, transport.initialChanges.length);
    });

    test('requestSync asks for the state and merges the reply', () async {
      final transport = _FakeRelayTransport(
        documentId: documentId,
        initialChanges: blobsOfText('hello'),
      );
      final client = buildClient(transport);
      await client.connect();
      await pump();

      await client.requestSync();
      await pump();

      expect(
        transport.received.whereType<RelayStateRequestMessage>(),
        hasLength(1),
      );
      // The second welcome re-imported the same state: no duplication.
      expect(handler.value, 'hello');
    });

    test('messages of other rooms are ignored', () async {
      final transport = _FakeRelayTransport(documentId: documentId);
      final client = buildClient(transport);
      await client.connect();

      final remote = blobsOfText('hi');
      transport.push(
        RelayChangesMessage(
          documentId: 'other-room',
          changes: remote,
          seq: remote.length,
        ),
      );
      await pump();

      expect(handler.value, isEmpty);
      expect(client.connectionStatusValue, ConnectionStatus.connected);
    });

    test('an undecodable frame is dropped without poisoning the stream',
        () async {
      final transport = _FakeRelayTransport(documentId: documentId);
      final client = buildClient(transport);
      await client.connect();

      transport.pushRaw([0, 1, 2, 3]);
      await pump();

      final remote = blobsOfText('hi');
      transport.push(
        RelayChangesMessage(
          documentId: documentId,
          changes: remote,
          seq: remote.length,
        ),
      );
      await pump();

      expect(handler.value, 'hi');
    });

    test('sendChange enqueues while disconnected and pushes after connect',
        () async {
      final transport = _FakeRelayTransport(documentId: documentId);
      final client = buildClient(transport);

      handler.insert(0, 'a');
      await pump();
      expect(client.pendingChangesCount, 1);

      await client.connect();
      await pump();
      await pump();

      expect(transport.received.whereType<RelayPushMessage>(), isNotEmpty);
      expect(client.pendingChangesCount, 0);
    });
  });
}
