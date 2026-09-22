@TestOn('vm')
library;

import 'dart:io';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/relay_server.dart';
import 'package:crdt_socket_sync_dart_frog/relay.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../utils/serve.dart';

/// The handler is thin, so this is about the protocol working through the
/// route: a real socket upgraded by Dart Frog joins a room.
void main() {
  group('crdtRelayWebSocketHandler', () {
    late InMemoryRelayStore store;
    late RelaySessionHost host;
    late HttpServer server;
    late Uri url;

    setUp(() async {
      store = InMemoryRelayStore();
      host = RelaySessionHost(store: store);
      (server, url) = await serveOnLoopback(crdtRelayWebSocketHandler(host));
    });

    tearDown(() async {
      await host.dispose();
      await server.close(force: true);
    });

    test('a relay client joins a room through the route', () async {
      const roomId = 'room-1';
      await host.start();

      final codec = JsonMessageCodec<Message>(
        toJson: (message) => message.toJson(),
        fromJson: (json) =>
            RelayMessage.fromJson(json) ?? Message.fromJson(json),
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

      final hello = codec.encode(
        RelayHelloMessage(documentId: roomId, author: PeerId.generate()),
      )!;
      channel.sink.add(hello);
      await settle();

      final welcome = replies.single as RelayWelcomeMessage;
      expect(welcome.documentId, roomId);
      expect(welcome.sessionId, isNotEmpty);

      await channel.sink.close();
    });
  });
}
