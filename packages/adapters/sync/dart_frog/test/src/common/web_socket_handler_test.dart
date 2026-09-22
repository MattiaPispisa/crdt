@TestOn('vm')
library;

import 'dart:io';

import 'package:crdt_socket_sync/server.dart';
import 'package:crdt_socket_sync_dart_frog/src/common/web_socket_handler.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../utils/serve.dart';

/// The seam both modes share: a socket upgraded by Dart Frog reaches the host
/// as a session, and a refused one is hung up on.
void main() {
  group('hostWebSocketHandler', () {
    late InMemoryCRDTServerRegistry registry;
    late DocumentSessionHost host;
    late HttpServer server;
    late Uri url;

    setUp(() async {
      registry = InMemoryCRDTServerRegistry();
      host = DocumentSessionHost(serverRegistry: registry);
      (server, url) = await serveOnLoopback(
        hostWebSocketHandler(
          host,
          protocols: null,
          allowedOrigins: null,
          pingInterval: null,
        ),
      );
    });

    tearDown(() async {
      await host.dispose();
      await registry.clear();
      await server.close(force: true);
    });

    test('an upgraded request becomes a session on the host', () async {
      await host.start();

      final events = <ServerEvent>[];
      host.serverEvents.listen(events.add);

      final channel = WebSocketChannel.connect(url);
      await channel.ready;
      await settle();

      expect(
        events.map((e) => e.type),
        contains(ServerEventType.clientConnected),
      );

      await channel.sink.close();
    });

    test('a stopped host hangs up instead of leaving the socket open',
        () async {
      await host.start();
      await host.stop();

      final channel = WebSocketChannel.connect(url);
      await channel.ready;

      // The refusal closes the connection from the server side, which the
      // client sees as its stream ending. Without it the client would sit on
      // a socket nobody is reading.
      await expectLater(channel.stream.drain<void>(), completes);
    });

    test('a request that is not an upgrade is answered, not accepted',
        () async {
      await host.start();

      final events = <ServerEvent>[];
      host.serverEvents.listen(events.add);

      final response = await HttpClient()
          .getUrl(url.replace(scheme: 'http'))
          .then((r) => r.close());
      await settle();

      expect(response.statusCode, isNot(HttpStatus.switchingProtocols));
      expect(
        events.map((e) => e.type),
        isNot(contains(ServerEventType.clientConnected)),
      );
    });
  });
}
