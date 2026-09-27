@TestOn('vm')
library;

import 'dart:io';

import 'package:crdt_socket_sync/server.dart';
import 'package:crdt_socket_sync_dart_frog/sync.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:test/test.dart';

import '../utils/serve.dart';

void main() {
  group('crdtSyncHostProvider', () {
    test('exposes the host under the type context.read matches on', () async {
      final registry = InMemoryCRDTServerRegistry();
      final host = DocumentSessionHost(serverRegistry: registry);

      DocumentSessionHost? read;

      final handler = ((RequestContext context) {
        read = context.read<DocumentSessionHost>();
        return Response(body: 'ok');
      }).use(crdtSyncHostProvider(host));

      final (server, url) = await serveOnLoopback(handler);
      await HttpClient()
          .getUrl(url.replace(scheme: 'http'))
          .then((r) => r.close());

      expect(read, same(host));

      await server.close(force: true);
      await host.dispose();
      await registry.clear();
    });
  });
}
