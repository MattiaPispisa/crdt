import 'dart:io';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/web_socket_client.dart';
import 'package:crdt_socket_sync_client_example/socket_sync.dart';
import 'package:en_logger/en_logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;
  late SocketSync sync;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('socket_sync_test');
    Hive.init(directory.path);
    sync = SocketSync(
      settings: await Hive.openBox<String>('settings'),
      defaultUrl: 'ws://localhost:1',
      logger: EnLogger(),
    );
  });

  tearDown(() async {
    await Hive.close();
    directory.deleteSync(recursive: true);
  });

  test('saved settings win over the defaults', () async {
    expect(sync.url, 'ws://localhost:1');

    await sync.save(url: 'ws://example.org', name: 'Ada');

    expect(sync.url, 'ws://example.org');
    expect(sync.name, 'Ada');
  });

  test('the client syncs the document at the saved url, with awareness', () {
    final document = CRDTDocument(documentId: 'doc');

    final client = sync.createClient(document, sync.peers.single);

    expect(client, isA<WebSocketClient>());
    expect((client as WebSocketClient).url, sync.url);
    expect(client.author, document.peerId);
    expect(client.plugins.whereType<ClientAwarenessPlugin>(), hasLength(1));
    client.dispose();
    document.dispose();
  });
}
