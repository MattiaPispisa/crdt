import 'dart:io';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/web_socket_client.dart';
import 'package:test/test.dart';
import 'package:{{name}}_server/{{name}}_server.dart';
import 'package:{{name}}_shared/{{name}}_shared.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('{{name}}_server');
  });

  tearDown(() => directory.delete(recursive: true));

  Future<SyncServer> start() {
    return SyncServer.start(
      directory: directory.path,
      host: InternetAddress.loopbackIPv4,
      port: 0,
    );
  }

  test(
    'a change reaches a second client and survives a restart',
    () async {
      var server = await start();

      final writer = await _Peer.connect(server.port);
      writer.probe.insert(0, 'hello');

      final reader = await _Peer.connect(server.port);
      await _until(() => reader.probe.value == 'hello');
      await writer.close();
      await reader.close();

      await server.stop();
      server = await start();

      final third = await _Peer.connect(server.port);
      await _until(() => third.probe.value == 'hello');
      await third.close();
      await server.stop();
    },
{{^storage_implemented}}
    skip: 'Write the storage backend in lib/src/storage_backend.dart first.',
{{/storage_implemented}}
  );
}

/// A client with its own document.
class _Peer {
  _Peer._(this.document, this.client);

  static Future<_Peer> connect(int port) async {
    final document = CRDTDocument(documentId: documentId);
    openHandlers(document);
    final client = WebSocketClient(
      url: 'ws://127.0.0.1:$port',
      document: document,
      author: document.peerId,
    );
    expect(await client.connect(), isTrue);
    return _Peer._(document, client);
  }

  final CRDTDocument document;
  final WebSocketClient client;

  /// A text handler the test writes to, whatever the schema holds.
  CRDTFugueTextHandler get probe {
    return document.handler(CRDTFugueTextHandler.spec, 'probe');
  }

  Future<void> close() async {
    await client.disconnect();
    client.dispose();
    document.dispose();
  }
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for the condition.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
