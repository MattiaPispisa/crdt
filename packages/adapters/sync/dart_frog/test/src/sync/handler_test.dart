@TestOn('vm')
library;

import 'dart:io';

// `Handler` is a CRDT handler in crdt_lf and a request handler in dart_frog.
import 'package:crdt_lf/crdt_lf.dart' hide Handler;
import 'package:crdt_socket_sync/server.dart';
import 'package:crdt_socket_sync_dart_frog/sync.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../utils/serve.dart';

/// The handler is thin, so this is about the protocol working through the
/// route: a real socket upgraded by Dart Frog completes the handshake.
void main() {
  group('crdtSyncWebSocketHandler', () {
    late InMemoryCRDTServerRegistry registry;
    late DocumentSessionHost host;
    late HttpServer server;
    late Uri url;

    setUp(() async {
      registry = InMemoryCRDTServerRegistry();
      host = DocumentSessionHost(serverRegistry: registry);
      (server, url) = await serveOnLoopback(crdtSyncWebSocketHandler(host));
    });

    tearDown(() async {
      await host.dispose();
      await registry.clear();
      await server.close(force: true);
    });

    test('a client completes the handshake through the route', () async {
      const documentId = 'doc-1';
      await registry.addDocument(documentId);
      await host.start();

      final codec = JsonMessageCodec<Message>(
        toJson: (message) => message.toJson(),
        fromJson: (json) =>
            SyncMessage.fromJson(json) ?? Message.fromJson(json),
      );

      final channel = WebSocketChannel.connect(url);
      await channel.ready;

      final replies = <Message>[];
      channel.stream.listen((frame) {
        final message = codec.decode(bytesOf(frame));
        if (message != null) {
          replies.add(message);
        }
      });

      final handshake = codec.encode(
        HandshakeRequestMessage(
          author: PeerId.generate(),
          documentId: documentId,
          versionVector: VersionVector({}),
        ),
      )!;
      channel.sink.add(handshake);
      await settle();

      expect(replies.single, isA<HandshakeResponseMessage>());

      await channel.sink.close();
    });
  });
}
