@TestOn('vm')
library;

import 'dart:async';

import 'package:crdt_socket_sync_serverpod/src/common/relic_web_socket_connection.dart';
import 'package:serverpod/serverpod.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../utils/serve.dart';

void main() {
  group('RelicWebSocketConnection', () {
    late Serverpod pod;
    late Uri url;
    late Completer<RelicWebSocketConnection> accepted;

    setUp(() async {
      accepted = Completer<RelicWebSocketConnection>();
      (pod, url) = await serveRoute(
        ResultRoute(
          () => WebSocketUpgrade(
            (ws) => accepted.complete(RelicWebSocketConnection(ws)),
          ),
        ),
      );
    });

    tearDown(() => stopPod(pod));

    test('text and binary frames both arrive as bytes', () async {
      final channel = WebSocketChannel.connect(url);
      await channel.ready;
      final connection = await accepted.future;

      final received = <List<int>>[];
      connection.incoming.listen(received.add);

      channel.sink
        ..add('hi')
        ..add([1, 2, 3]);
      await settle();

      expect(received, [
        [104, 105],
        [1, 2, 3],
      ]);

      await channel.sink.close();
    });

    test('send reaches the peer', () async {
      final channel = WebSocketChannel.connect(url);
      await channel.ready;
      final connection = await accepted.future;

      final received = <List<int>>[];
      channel.stream.listen((frame) => received.add(bytesOf(frame)));

      await connection.send([4, 5, 6]);
      await settle();

      expect(received, [
        [4, 5, 6],
      ]);

      await channel.sink.close();
    });

    test('close ends the peer stream and the connection', () async {
      final channel = WebSocketChannel.connect(url);
      await channel.ready;
      final connection = await accepted.future;
      final incomingDone = connection.incoming.drain<void>();

      expect(connection.isConnected, isTrue);

      await connection.close();

      await expectLater(channel.stream.drain<void>(), completes);
      await expectLater(incomingDone, completes);
      expect(connection.isConnected, isFalse);
    });
  });
}
