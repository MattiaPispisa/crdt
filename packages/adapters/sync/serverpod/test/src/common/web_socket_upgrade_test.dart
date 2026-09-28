@TestOn('vm')
library;

import 'package:crdt_socket_sync/server.dart';
import 'package:crdt_socket_sync_serverpod/src/common/web_socket_upgrade.dart';
import 'package:serverpod/serverpod.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../utils/serve.dart';

void main() {
  group('hostWebSocketUpgrade', () {
    late InMemoryCRDTServerRegistry registry;
    late DocumentSessionHost host;
    late Serverpod pod;
    late Uri url;

    Future<void> serveUpgrade({Duration? pingInterval}) async {
      (pod, url) = await serveRoute(
        ResultRoute(
          () => hostWebSocketUpgrade(
            host,
            pingInterval: pingInterval,
            allowAnyOrigin: false,
          ),
        ),
      );
    }

    setUp(() {
      registry = InMemoryCRDTServerRegistry();
      host = DocumentSessionHost(serverRegistry: registry);
    });

    tearDown(() async {
      await host.dispose();
      await registry.clear();
      await stopPod(pod);
    });

    test('an upgraded request becomes a session on the host', () async {
      await serveUpgrade(pingInterval: const Duration(seconds: 5));
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

    test(
      'a stopped host hangs up instead of leaving the socket open',
      () async {
        await serveUpgrade();
        await host.start();
        await host.stop();

        final channel = WebSocketChannel.connect(url);
        await channel.ready;

        await expectLater(channel.stream.drain<void>(), completes);
      },
    );
  });
}
