@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/server.dart';
import 'package:crdt_socket_sync_serverpod/sync.dart';
// `Message` is a protocol message in crdt_socket_sync and a request or
// response in serverpod.
import 'package:serverpod/serverpod.dart' hide Message;
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../utils/serve.dart';

class _RefusingRoute extends CrdtSyncRoute {
  _RefusingRoute(super.sessionHost);

  @override
  FutureOr<Result> handleCall(Session session, Request request) {
    return Response.unauthorized();
  }
}

void main() {
  group('CrdtSyncRoute', () {
    late InMemoryCRDTServerRegistry registry;
    late DocumentSessionHost host;
    late Serverpod pod;
    late Uri url;

    setUp(() {
      registry = InMemoryCRDTServerRegistry();
      host = DocumentSessionHost(serverRegistry: registry);
    });

    tearDown(() async {
      await host.dispose();
      await registry.clear();
      await stopPod(pod);
    });

    test('a client completes the handshake through the route', () async {
      (pod, url) = await serveRoute(CrdtSyncRoute(host), path: '/sync');
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

    test('a subclass refuses before the upgrade with a status code', () async {
      (pod, url) = await serveRoute(_RefusingRoute(host), path: '/sync');
      await host.start();

      final events = <ServerEvent>[];
      host.serverEvents.listen(events.add);

      final channel = WebSocketChannel.connect(url);
      await expectLater(
        channel.ready,
        throwsA(isA<WebSocketChannelException>()),
      );

      final response = await HttpClient()
          .getUrl(url.replace(scheme: 'http'))
          .then((r) => r.close());
      await settle();

      expect(response.statusCode, HttpStatus.unauthorized);
      expect(
        events.map((e) => e.type),
        isNot(contains(ServerEventType.clientConnected)),
      );
    });
  });
}
