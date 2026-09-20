import 'package:crdt_socket_sync_dart_frog_example/src/hosts.dart';
import 'package:test/test.dart';

// No `@TestOn('vm')`: the hosts only reach `server.dart` and
// `relay_server.dart`, which are free of `dart:io`, so this file runs on
// Chrome too and doubles as a check that they stay that way.
void main() {
  group('ExampleHosts', () {
    test('is usable before start(), which is what the middleware needs', () {
      // `_middleware.dart` reads the hosts when Dart Frog builds the handler
      // tree, before any request. Construction must not depend on `start()`.
      final hosts = ExampleHosts();
      addTearDown(hosts.dispose);

      expect(hosts.sync.isRunning, isFalse);
      expect(hosts.relay.isRunning, isFalse);
    });

    test('start() registers the example document and runs both hosts',
        () async {
      final hosts = ExampleHosts();
      addTearDown(hosts.dispose);

      await hosts.start();

      expect(hosts.sync.isRunning, isTrue);
      expect(hosts.relay.isRunning, isTrue);
      expect(
        await hosts.sync.serverRegistry.hasDocument(exampleDocumentId),
        isTrue,
      );
    });

    test('dispose() stops them', () async {
      final hosts = ExampleHosts();
      await hosts.start();

      await hosts.dispose();

      expect(hosts.sync.isRunning, isFalse);
      expect(hosts.relay.isRunning, isFalse);
    });
  });
}
