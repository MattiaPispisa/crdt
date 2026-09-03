@TestOn('vm')
library;

import 'dart:async';
import 'dart:ui';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/relay_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:greyhound_markdown_client/src/services/awareness/awareness_service.dart';

/// Minimal in-memory [RelaySocketClient] to drive the awareness plugin
/// without a real transport. Extends the abstract class so the plugin
/// back-reference is wired in the constructor.
class _FakeClient extends RelaySocketClient {
  _FakeClient({required this.document, super.plugins});

  @override
  final CRDTDocument document;

  final List<Message> sent = [];

  @override
  PeerId get author => document.peerId;

  @override
  String? get sessionId => 'me';

  @override
  int get pendingChangesCount => 0;

  @override
  List<Change> get pendingChanges => const [];

  @override
  void restorePendingChanges(Iterable<Change> changes) {}

  @override
  int get lastKnownSeq => 0;

  @override
  ConnectionStatus get connectionStatusValue => ConnectionStatus.connected;

  @override
  Stream<ConnectionStatus> get connectionStatus => const Stream.empty();

  @override
  Stream<Message> get messages => const Stream.empty();

  @override
  Future<bool> connect() async => true;

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> sendMessage(Message message) async => sent.add(message);

  @override
  Future<void> sendChange(Change change) async {}

  @override
  Future<void> requestSync() async {}

  @override
  void dispose() {}
}

void main() {
  const roomId = 'room-1';

  late CRDTDocument document;
  late AwarenessService service;
  late _FakeClient client;

  setUp(() {
    document = CRDTDocument(documentId: roomId);
    service = AwarenessService(
      name: 'Me',
      color: const Color(0xFF112233),
      throttle: Duration.zero,
    );
    // Attaching the plugin wires its back-reference to the client.
    client = _FakeClient(document: document, plugins: [service.plugin]);
  });

  tearDown(() {
    service.dispose();
    client.dispose();
    document.dispose();
  });

  ClientAwareness peer(String id, Map<String, dynamic> metadata) =>
      ClientAwareness(clientId: id, metadata: metadata);

  test(
    'maps peer metadata to PeerState and excludes self and empty peers',
    () async {
      service.plugin.onMessage(
        AwarenessStateMessage(
          documentId: roomId,
          awareness: DocumentAwareness(
            documentId: roomId,
            states: {
              // self: must be excluded (client.sessionId == 'me')
              'me': peer('me', {'name': 'Me', 'color': 0xFF112233}),
              // a real peer with presence
              'peer1': peer('peer1', {'name': 'Ann', 'color': 0xFF3949AB}),
              // a fresh joiner with no metadata yet: must be excluded
              'peer2': peer('peer2', <String, dynamic>{}),
            },
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(service.peers.value.keys, ['peer1']);
      final ann = service.peers.value['peer1']!;
      expect(ann.name, 'Ann');
      expect(ann.color, const Color(0xFF3949AB));
      expect(ann.base, isNull);
    },
  );

  test('publishes a cursor update and withdraws it on null anchors', () async {
    final text = CRDTFugueTextHandler(document, 'content')..insert(0, 'ab');
    final anchor = text.stablePositionAt(1);
    expect(anchor, isNotNull);

    service.setLocalCursor(anchor, null);
    await Future<void>.delayed(Duration.zero);

    final published = client.sent.whereType<AwarenessUpdateMessage>().toList();
    expect(published, isNotEmpty);
    final cursor =
        published.last.state.metadata['cursor'] as Map<String, dynamic>?;
    expect(cursor, isNotNull);
    expect(cursor!['base'], isNotNull);

    // Blur: null anchors withdraw the cursor.
    client.sent.clear();
    service.setLocalCursor(null, null);
    await Future<void>.delayed(Duration.zero);

    final withdrawn = client.sent.whereType<AwarenessUpdateMessage>().toList();
    expect(withdrawn, isNotEmpty);
    expect(withdrawn.last.state.metadata['cursor'], isNull);
  });
}
