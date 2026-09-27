@TestOn('vm')
library;

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/server.dart';
import 'package:persistence_conformance/persistence_conformance.dart';
import 'package:test/test.dart';

import '../../utils/fake_connection.dart';

/// The CRDT-aware host, driven entirely through `acceptConnection`.
///
/// No `HttpServer`, no upgrade, no `dart:io` — which is the point: it proves
/// the document protocol, snapshot alignment included, is transport-free and
/// can be embedded in someone else's server.
void main() {
  group('DocumentSessionHost', () {
    late InMemoryCRDTServerRegistry registry;
    late DocumentSessionHost host;
    late JsonMessageCodec<Message> codec;
    late List<ServerEvent> events;

    setUp(() {
      registry = InMemoryCRDTServerRegistry();
      host = DocumentSessionHost(serverRegistry: registry);
      codec = JsonMessageCodec<Message>(
        toJson: (message) => message.toJson(),
        fromJson: (json) =>
            SyncMessage.fromJson(json) ?? Message.fromJson(json),
      );
      events = [];
      host.serverEvents.listen(events.add);
    });

    tearDown(() async {
      await host.dispose();
      await registry.clear();
    });

    /// Applies a single change so the registry document has a non-empty
    /// state, and returns the resulting server version vector.
    ///
    /// [into] defaults to the in-memory registry of the group.
    Future<VersionVector> seedServerChange(
      String documentId, {
      CRDTServerRegistry? into,
    }) async {
      final target = into ?? registry;
      final authorDoc = CRDTDocument(peerId: PeerId.generate());
      CRDTListHandler<String>(
        authorDoc,
        'list',
        handlerType: 'CRDTListHandler<String>',
      ).insert(0, 'a');
      final change = authorDoc.exportChanges().first;
      await target.applyChange(documentId, change);
      return (await target.getDocument(documentId))!.getVersionVector();
    }

    /// Accepts a connection and completes the handshake on it.
    ///
    /// [on] defaults to the host of the group.
    Future<FakeTransportConnection> addClient(
      String documentId, {
      DocumentSessionHost? on,
    }) async {
      final connection = FakeTransportConnection();
      (on ?? host).acceptConnection(connection);
      await Future<void>.delayed(Duration.zero);

      connection.receive(
        codec.encode(
          HandshakeRequestMessage(
            author: PeerId.generate(),
            documentId: documentId,
            versionVector: VersionVector({}),
          ),
        )!,
      );
      await Future<void>.delayed(Duration.zero);
      return connection;
    }

    test('completes a handshake over a plain TransportConnection', () async {
      final documentId = PeerId.generate().id;
      await registry.addDocument(documentId);
      await host.start();

      final connection = await addClient(documentId);

      final replies = connection.sent.map(codec.decode).nonNulls.toList();
      expect(replies.single, isA<HandshakeResponseMessage>());
      expect(
        events.map((e) => e.type),
        containsAllInOrder([
          ServerEventType.started,
          ServerEventType.clientConnected,
          ServerEventType.clientHandshake,
        ]),
      );
    });

    test('snapshots and prunes once every client confirms the state', () async {
      final documentId = PeerId.generate().id;
      await registry.addDocument(documentId);
      final serverVersion = await seedServerChange(documentId);
      await host.start();

      final first = await addClient(documentId);
      final second = await addClient(documentId);

      // Both handshook with an empty version vector: nobody is aligned yet.
      expect(await registry.getLatestSnapshot(documentId), isNull);

      for (final connection in [first, second]) {
        connection.receive(
          codec.encode(
            PingMessage(
              documentId: documentId,
              timestamp: 0,
              versionVector: serverVersion,
            ),
          )!,
        );
        await Future<void>.delayed(Duration.zero);
      }

      expect(await registry.getLatestSnapshot(documentId), isA<Snapshot>());
      expect(
        events.where((e) => e.type == ServerEventType.snapshotCreated),
        hasLength(1),
      );
    });

    test('does not snapshot while a client is behind', () async {
      final documentId = PeerId.generate().id;
      await registry.addDocument(documentId);
      final serverVersion = await seedServerChange(documentId);
      await host.start();

      final aligned = await addClient(documentId);
      final behind = await addClient(documentId);

      aligned.receive(
        codec.encode(
          PingMessage(
            documentId: documentId,
            timestamp: 0,
            versionVector: serverVersion,
          ),
        )!,
      );
      behind.receive(
        codec.encode(
          PingMessage(
            documentId: documentId,
            timestamp: 0,
            versionVector: VersionVector({}),
          ),
        )!,
      );
      await Future<void>.delayed(Duration.zero);

      expect(await registry.getLatestSnapshot(documentId), isNull);
      expect(
        events.where((e) => e.type == ServerEventType.snapshotCreated),
        isEmpty,
      );
    });

    test('a stopped host takes no snapshot, however aligned the clients are',
        () async {
      final documentId = PeerId.generate().id;
      await registry.addDocument(documentId);
      final serverVersion = await seedServerChange(documentId);
      await host.start();

      await addClient(documentId);
      await host.stop();

      await host.maybeTakeAlignedSnapshot(documentId);

      expect(serverVersion.isEmpty, isFalse);
      expect(await registry.getLatestSnapshot(documentId), isNull);
    });

    test('rebroadcasts an applied change to the other clients', () async {
      final documentId = PeerId.generate();
      await registry.addDocument(documentId.id);
      await host.start();

      final author = await addClient(documentId.id);
      final listener = await addClient(documentId.id);

      final clientDoc = CRDTDocument(peerId: documentId);
      CRDTListHandler<String>(
        clientDoc,
        'list',
        handlerType: 'CRDTListHandler<String>',
      ).insert(0, 'Hello');
      final change = clientDoc.exportChanges().first;

      author.receive(
        codec.encode(
          ChangeMessage(change: change, documentId: documentId.id),
        )!,
      );
      await Future<void>.delayed(Duration.zero);

      final relayed = listener.sent
          .map(codec.decode)
          .nonNulls
          .whereType<ChangeMessage>()
          .toList();
      expect(relayed.single.change.id, change.id);

      // The author is excluded from its own broadcast.
      expect(
        author.sent.map(codec.decode).nonNulls.whereType<ChangeMessage>(),
        isEmpty,
      );
    });

    test('sends each snapshot of a persistent registry to its clients',
        () async {
      final persistent = PersistentServerRegistry(
        backend: InMemoryStorageBackend(),
        writeDelay: Duration.zero,
      );
      final persistentHost = DocumentSessionHost(serverRegistry: persistent);
      addTearDown(persistentHost.dispose);

      final documentId = PeerId.generate().id;
      await persistent.addDocument(documentId);
      await seedServerChange(documentId, into: persistent);
      await persistentHost.start();
      final client = await addClient(documentId, on: persistentHost);

      await persistent.createSnapshot(documentId);
      await pumpEventQueue();

      final statuses = client.sent
          .map(codec.decode)
          .nonNulls
          .whereType<DocumentStatusMessage>()
          .toList();
      expect(statuses.single.snapshot, isA<Snapshot>());
    });

    test('dispose() closes the registry', () async {
      await host.start();
      await host.dispose();

      // A closed in-memory registry is empty; closing twice is harmless, so
      // the tearDown that follows stays valid.
      expect(await registry.documentCount, 0);
    });
  });
}
