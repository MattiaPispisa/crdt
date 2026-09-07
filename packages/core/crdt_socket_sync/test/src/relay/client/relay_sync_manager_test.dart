import 'dart:convert';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/relay/client/relay_sync_manager.dart';
import 'package:crdt_socket_sync/src/relay/common/common.dart';
import 'package:test/test.dart';

import '../../utils/mock_relay_client.dart';

void main() {
  group('RelaySyncManager', () {
    late CRDTDocument document;
    late CRDTFugueTextHandler handler;
    late MockRelaySocketClient client;
    late RelaySyncManager manager;

    setUp(() {
      document = CRDTDocument(peerId: PeerId.generate());
      handler = CRDTFugueTextHandler(document, 'content');
      client = MockRelaySocketClient(
        document: document,
        author: document.peerId,
      );
      manager = RelaySyncManager(document: document, client: client);
    });

    tearDown(() {
      manager.dispose();
      client.dispose();
      document.dispose();
    });

    Future<void> pump() => Future<void>.delayed(Duration.zero);

    RelayWelcomeMessage welcome({
      String? snapshot,
      List<String> changes = const [],
      int seq = 0,
      bool compact = false,
    }) {
      return RelayWelcomeMessage(
        documentId: document.documentId,
        sessionId: 'test-session-id',
        snapshot: snapshot,
        changes: changes,
        seq: seq,
        logLength: changes.length,
        compact: compact,
      );
    }

    /// Blobs of every change of a fresh document containing [text].
    List<String> blobsOfText(String text) {
      final peer = CRDTDocument(peerId: PeerId.generate());
      CRDTFugueTextHandler(peer, 'content').insert(0, text);
      return peer
          .exportChanges()
          .map((change) => base64Encode(change.toBytes()))
          .toList();
    }

    test('local changes are not pushed before the welcome', () async {
      handler.insert(0, 'a');
      await pump();

      expect(client.getSentMessagesOfType<RelayPushMessage>(), isEmpty);
      expect(manager.pendingChangesCount, 1);
    });

    test('welcome imports the room state and flushes the queue', () async {
      handler.insert(0, 'a');
      await pump();

      final remote = blobsOfText('bc');
      await manager.onWelcome(
        welcome(changes: remote, seq: remote.length),
      );
      await pump();

      // Remote state merged with the local unacked insert.
      expect(handler.value, contains('bc'));
      expect(handler.value, contains('a'));
      expect(manager.lastKnownSeq, remote.length);

      final push = client.getSentMessagesOfType<RelayPushMessage>().single;
      expect(push.changes, hasLength(1));
    });

    test('a single push is in flight until its ack', () async {
      await manager.onWelcome(welcome());

      handler.insert(0, 'a');
      await pump();
      handler.insert(1, 'b');
      await pump();

      // The second change queued behind the in-flight push.
      var pushes = client.getSentMessagesOfType<RelayPushMessage>();
      expect(pushes, hasLength(1));

      await manager.onAck(
        RelayAckMessage(
          documentId: document.documentId,
          seq: 1,
          count: 1,
          logLength: 1,
          compact: false,
        ),
      );

      pushes = client.getSentMessagesOfType<RelayPushMessage>();
      expect(pushes, hasLength(2));
      expect(pushes.last.changes, hasLength(1));
      expect(manager.pendingChangesCount, 1);
    });

    test('unacked changes survive a connection loss and are re-pushed',
        () async {
      await manager.onWelcome(welcome());
      handler.insert(0, 'a');
      await pump();
      expect(client.getSentMessagesOfType<RelayPushMessage>(), hasLength(1));

      // The connection drops with the push in flight: no ack will come.
      manager.onConnectionLost();
      client.clearSentMessages();

      await manager.onWelcome(welcome());
      final push = client.getSentMessagesOfType<RelayPushMessage>().single;
      expect(push.changes, hasLength(1));
      expect(manager.pendingChangesCount, 1);
    });

    test('rebroadcast changes are imported and re-delivery is harmless',
        () async {
      await manager.onWelcome(welcome());

      final remote = blobsOfText('hi');
      final message = RelayChangesMessage(
        documentId: document.documentId,
        changes: remote,
        seq: remote.length,
        from: 'other',
      );

      manager
        ..onChanges(message)
        ..onChanges(message);

      expect(handler.value, 'hi');
      expect(manager.lastKnownSeq, remote.length);
    });

    test('a compact welcome triggers a snapshot upload', () async {
      final remote = blobsOfText('hi');
      await manager.onWelcome(
        welcome(changes: remote, seq: remote.length, compact: true),
      );

      final upload =
          client.getSentMessagesOfType<RelaySnapshotUploadMessage>().single;
      expect(upload.upToSeq, remote.length);

      // The uploaded snapshot alone rebuilds the document.
      final replica = CRDTDocument(peerId: PeerId.generate());
      final replicaHandler = CRDTFugueTextHandler(replica, 'content');
      replica.import(
        snapshot: Snapshot.fromBytes(base64Decode(upload.snapshot)),
        merge: true,
        pruneHistory: false,
      );
      expect(replicaHandler.value, 'hi');
    });

    test('a compact ack never covers sequences the client has not imported',
        () async {
      final remote = blobsOfText('hi');
      await manager.onWelcome(
        welcome(changes: remote, seq: remote.length),
      );

      handler.insert(0, 'a');
      await pump();

      // The ack says the log reached seq 10: the sequences between the
      // welcome and this client's own push belong to another client and
      // were not rebroadcast yet.
      await manager.onAck(
        RelayAckMessage(
          documentId: document.documentId,
          seq: 10,
          count: 1,
          logLength: 10,
          compact: true,
        ),
      );

      final upload =
          client.getSentMessagesOfType<RelaySnapshotUploadMessage>().single;
      // Covering up to 10 would delete the un-imported entries: the upload
      // stops at the last contiguous imported sequence.
      expect(upload.upToSeq, remote.length);
    });

    test('a failed push returns the window to the pending state', () async {
      await manager.onWelcome(welcome());
      client.setShouldThrowOnSendMessage = true;

      handler.insert(0, 'a');
      await pump();
      expect(manager.pendingChangesCount, 1);

      // Once the connection is back, the blob goes out.
      client
        ..setShouldThrowOnSendMessage = false
        ..clearSentMessages();
      await manager.onWelcome(welcome());
      expect(client.getSentMessagesOfType<RelayPushMessage>(), hasLength(1));
    });

    group('welcome reconciliation', () {
      /// A document holding [text], as a restart would restore one: every
      /// change reaches it through `importChanges`, so it is imported, never
      /// local, and `localChanges` never carries it.
      void restoreIntoDocument(String text) {
        final peer = CRDTDocument(peerId: PeerId.generate());
        CRDTFugueTextHandler(peer, 'content').insert(0, text);
        document.importChanges(peer.exportChanges());
      }

      test('pushes what the document holds and the welcome did not carry',
          () async {
        // Written offline in a previous session, read back from storage.
        restoreIntoDocument('offline');
        await pump();
        expect(
          manager.pendingChangesCount,
          0,
          reason: 'an imported change never reaches localChanges',
        );

        await manager.onWelcome(welcome());

        final push = client.getSentMessagesOfType<RelayPushMessage>().single;
        expect(push.changes, hasLength(document.exportChanges().length));
      });

      test('does not push back what the welcome already carried', () async {
        final remote = blobsOfText('theirs');

        await manager.onWelcome(
          welcome(changes: remote, seq: remote.length),
        );

        expect(client.getSentMessagesOfType<RelayPushMessage>(), isEmpty);
        expect(manager.pendingChangesCount, 0);
      });

      test('does not push what the welcome snapshot already covers', () async {
        final peer = CRDTDocument(peerId: PeerId.generate());
        CRDTFugueTextHandler(peer, 'content').insert(0, 'theirs');
        final snapshot = peer.takeSnapshot(pruneHistory: false);
        // The document holds the changes; the relay holds only the snapshot.
        document.importChanges(peer.exportChanges());
        await pump();

        await manager.onWelcome(
          welcome(snapshot: base64Encode(snapshot.toBytes()), seq: 1),
        );

        expect(client.getSentMessagesOfType<RelayPushMessage>(), isEmpty);
      });

      test('queues an unacked change once, not twice', () async {
        handler.insert(0, 'a');
        await pump();
        expect(manager.pendingChangesCount, 1);

        // The welcome does not carry it, so reconciliation finds it too.
        await manager.onWelcome(welcome());

        final push = client.getSentMessagesOfType<RelayPushMessage>().single;
        expect(push.changes, hasLength(1));
      });
    });

    test('requestState sends a state request', () async {
      await manager.requestState();
      expect(
        client.getSentMessagesOfType<RelayStateRequestMessage>(),
        hasLength(1),
      );
    });
  });
}
