@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

// `Handler` is a CRDT handler in crdt_lf and a request handler in dart_frog.
import 'package:crdt_lf/crdt_lf.dart' hide Handler;
import 'package:crdt_socket_sync/relay_server.dart';
import 'package:crdt_socket_sync/server.dart';
import 'package:crdt_socket_sync_dart_frog/crdt_socket_sync_dart_frog.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// The handlers are thin, so these tests are about the seam: does a real
/// WebSocket upgraded by Dart Frog end up as a live session on the host, and
/// does the protocol work over it.
void main() {
  group('crdtSyncWebSocketHandler', () {
    late InMemoryCRDTServerRegistry registry;
    late DocumentSessionHost host;
    late HttpServer server;
    late Uri url;

    setUp(() async {
      registry = InMemoryCRDTServerRegistry();
      host = DocumentSessionHost(serverRegistry: registry);
      (server, url) = await _serve(crdtSyncWebSocketHandler(host));
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
      await _settle();

      expect(
        events.map((e) => e.type),
        contains(ServerEventType.clientConnected),
      );

      await channel.sink.close();
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
        final message = codec.decode(_bytesOf(frame));
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
      await _settle();

      expect(replies.single, isA<HandshakeResponseMessage>());

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
  });

  group('crdtRelayWebSocketHandler', () {
    late InMemoryRelayStore store;
    late RelaySessionHost host;
    late HttpServer server;
    late Uri url;

    setUp(() async {
      store = InMemoryRelayStore();
      host = RelaySessionHost(store: store);
      (server, url) = await _serve(crdtRelayWebSocketHandler(host));
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
        final message = codec.decode(_bytesOf(frame));
        if (message != null) {
          replies.add(message);
        }
      });

      final hello = codec.encode(
        RelayHelloMessage(documentId: roomId, author: PeerId.generate()),
      )!;
      channel.sink.add(hello);
      await _settle();

      final welcome = replies.single as RelayWelcomeMessage;
      expect(welcome.documentId, roomId);
      expect(welcome.sessionId, isNotEmpty);

      await channel.sink.close();
    });
  });

  group('providers', () {
    test('expose the host under the type context.read matches on', () async {
      final registry = InMemoryCRDTServerRegistry();
      final syncHost = DocumentSessionHost(serverRegistry: registry);
      final relayHost = RelaySessionHost();

      DocumentSessionHost? readSync;
      RelaySessionHost? readRelay;

      final handler = ((RequestContext context) {
        readSync = context.read<DocumentSessionHost>();
        readRelay = context.read<RelaySessionHost>();
        return Response(body: 'ok');
      })
          .use(crdtSyncHostProvider(syncHost))
          .use(crdtRelayHostProvider(relayHost));

      final (server, url) = await _serve(handler);
      await HttpClient()
          .getUrl(url.replace(scheme: 'http'))
          .then((r) => r.close());

      expect(readSync, same(syncHost));
      expect(readRelay, same(relayHost));

      await server.close(force: true);
      await syncHost.dispose();
      await relayHost.dispose();
      await registry.clear();
    });
  });
}

/// Runs [handler] on a real loopback server and returns it with its ws URL.
Future<(HttpServer, Uri)> _serve(Handler handler) async {
  final server = await serve(handler, InternetAddress.loopbackIPv4, 0);
  return (server, Uri.parse('ws://127.0.0.1:${server.port}'));
}

/// Gives the socket a few turns to carry a frame both ways.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 100));

List<int> _bytesOf(dynamic frame) {
  if (frame is String) {
    return utf8.encode(frame);
  }
  return frame as List<int>;
}
