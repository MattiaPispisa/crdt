import 'package:crdt_socket_sync_dart_frog_relay_example/src/host.dart';
import 'package:test/test.dart';

// No `@TestOn('vm')`: the host only reaches `relay_server.dart`, which is
// free of `dart:io`, so this file runs on Chrome too and doubles as a check
// that it stays that way.
void main() {
  group('relayHost', () {
    test('is usable before start(), which is what the middleware needs', () {
      expect(relayHost.isRunning, isFalse);
    });

    test('starts and disposes', () async {
      expect(await relayHost.start(), isTrue);
      expect(relayHost.isRunning, isTrue);

      await relayHost.dispose();

      expect(relayHost.isRunning, isFalse);
    });
  });
}
