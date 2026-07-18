import 'dart:async';
import 'dart:ui';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:greyhound_markdown_client/src/config.dart';
import 'package:greyhound_markdown_client/src/model/protocol.dart';
import 'package:greyhound_markdown_client/src/services/awareness_service.dart';
import 'package:greyhound_markdown_client/src/services/sync_client.dart';

class _FakeSink implements WebSocketSink {
  _FakeSink(this.onFrame);

  final void Function(String frame) onFrame;

  @override
  void add(dynamic data) => onFrame(data as String);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeChannel implements WebSocketChannel {
  _FakeChannel() : controller = StreamController<dynamic>.broadcast();

  final StreamController<dynamic> controller;
  final List<ProtocolMessage> sent = [];

  void receive(ProtocolMessage message) => controller.add(message.encode());

  @override
  Stream<dynamic> get stream => controller.stream;

  @override
  WebSocketSink get sink =>
      _FakeSink((frame) => sent.add(ProtocolMessage.decode(frame)!));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late CRDTDocument doc;
  late CRDTFugueTextHandler text;
  late AwarenessService awareness;
  late _FakeChannel channel;
  late SyncClient client;

  WelcomeMessage emptyWelcome({bool compact = false}) => WelcomeMessage(
    snapshot: null,
    changes: const [],
    seq: 0,
    logLen: 0,
    peers: const {},
    compact: compact,
  );

  setUp(() {
    doc = CRDTDocument();
    text = CRDTFugueTextHandler(doc, kHandlerId);
    awareness = AwarenessService(
      name: 'Ann',
      color: const Color(0xFF112233),
      throttle: Duration.zero,
    );
    channel = _FakeChannel();
    client = SyncClient(
      roomId: 'room1',
      document: doc,
      awareness: awareness,
      channelFactory: (_) => channel,
    )..connect();
  });

  tearDown(() {
    client.dispose();
    awareness.dispose();
  });

  test(
    'local changes are queued, pushed after welcome, cleared on ack',
    () async {
      text.insert(0, 'hi');
      await Future<void>.delayed(Duration.zero);
      expect(client.pendingCount, 1);
      // Not handshaken yet: nothing pushed.
      expect(channel.sent.whereType<PushMessage>(), isEmpty);

      channel.receive(emptyWelcome());
      await Future<void>.delayed(Duration.zero);
      expect(client.status.value, SyncStatus.connected);
      final push = channel.sent.whereType<PushMessage>().single;
      expect(push.changes, hasLength(1));

      channel.receive(const AckMessage(seq: 1, logLen: 1, compact: false));
      await Future<void>.delayed(Duration.zero);
      expect(client.pendingCount, 0);
    },
  );

  test('welcome imports server state and seeds peers', () async {
    final remote = CRDTDocument();
    CRDTFugueTextHandler(remote, kHandlerId).insert(0, 'from server');
    final blobs = remote.exportChanges().map((c) => c.toBytes()).toList();

    channel.receive(
      WelcomeMessage(
        snapshot: null,
        changes: blobs,
        seq: blobs.length,
        logLen: blobs.length,
        peers: {
          'peer-b': {'name': 'Bob', 'color': 0xFF00FF00, 'cursor': null},
        },
        compact: false,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(text.value, 'from server');
    expect(awareness.peers.value['peer-b']?.name, 'Bob');
  });

  test('rebroadcast change frames apply to the document', () async {
    channel.receive(emptyWelcome());
    final remote = CRDTDocument();
    CRDTFugueTextHandler(remote, kHandlerId).insert(0, 'live');
    channel.receive(
      ChangeMessage(
        from: 'peer-b',
        changes: remote.exportChanges().map((c) => c.toBytes()).toList(),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(text.value, 'live');
  });

  test(
    'rebroadcast changes are imported; unacked queue survives reconnect',
    () async {
      channel.receive(emptyWelcome());
      await Future<void>.delayed(Duration.zero);
      channel.sent.clear();

      text.insert(0, 'abc');
      await Future<void>.delayed(Duration.zero);
      expect(channel.sent.whereType<PushMessage>(), hasLength(1));
      expect(client.pendingCount, 1);

      // Server dies before the ack: welcome from the new connection must
      // trigger a re-flush of the still-pending blob.
      channel.receive(emptyWelcome());
      await Future<void>.delayed(Duration.zero);
      expect(channel.sent.whereType<PushMessage>(), hasLength(2));
      expect(client.pendingCount, 1);

      channel.receive(const AckMessage(seq: 1, logLen: 1, compact: false));
      await Future<void>.delayed(Duration.zero);
      expect(client.pendingCount, 0);
    },
  );

  test('compact request uploads a snapshot', () async {
    text.insert(0, 'content to snapshot');
    channel.receive(emptyWelcome(compact: true));
    await Future<void>.delayed(Duration.zero);
    final upload = channel.sent.whereType<SnapshotMessage>().single;
    expect(upload.upto, 0);
    final restored = CRDTDocument();
    final restoredText = CRDTFugueTextHandler(restored, kHandlerId);
    restored.import(snapshot: Snapshot.fromBytes(upload.snapshot));
    expect(restoredText.value, 'content to snapshot');
  });

  test('awareness updates and peer_left maintain the peers map', () async {
    channel.receive(emptyWelcome());
    channel.receive(
      const AwarenessMessage(
        from: 'peer-c',
        state: {'name': 'Cy', 'color': 0xFFFF0000, 'cursor': null},
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(awareness.peers.value.keys, ['peer-c']);

    channel.receive(const PeerLeftMessage(clientId: 'peer-c'));
    await Future<void>.delayed(Duration.zero);
    expect(awareness.peers.value, isEmpty);
  });
}
