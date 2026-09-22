@TestOn('vm')
library;

import 'dart:io';

import 'package:crdt_socket_sync_dart_frog/relay.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:test/test.dart';

import '../utils/serve.dart';

void main() {
  group('crdtRelayHostProvider', () {
    test('exposes the host under the type context.read matches on', () async {
      final host = RelaySessionHost();

      RelaySessionHost? read;

      final handler = ((RequestContext context) {
        read = context.read<RelaySessionHost>();
        return Response(body: 'ok');
      }).use(crdtRelayHostProvider(host));

      final (server, url) = await serveOnLoopback(handler);
      await HttpClient()
          .getUrl(url.replace(scheme: 'http'))
          .then((r) => r.close());

      expect(read, same(host));

      await server.close(force: true);
      await host.dispose();
    });
  });
}
