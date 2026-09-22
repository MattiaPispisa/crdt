@TestOn('vm')
library;

import 'dart:io';

import 'package:crdt_socket_sync_dart_frog_example/src/host.dart';
import 'package:test/test.dart';

void main() {
  group('ExampleHost', () {
    late Directory dbDir;

    setUp(() async {
      dbDir = await Directory.systemTemp.createTemp('dart_frog_example_');
    });

    tearDown(() => dbDir.delete(recursive: true));

    test('open() creates the example document, leaving the host to start',
        () async {
      final example = await ExampleHost.open(dbPath: dbDir.path);
      addTearDown(example.dispose);

      expect(example.host.isRunning, isFalse);
      expect(
        await example.host.serverRegistry.hasDocument(exampleDocumentId),
        isTrue,
      );
    });

    test('the document survives a restart', () async {
      final first = await ExampleHost.open(dbPath: dbDir.path);
      await first.dispose();

      final second = await ExampleHost.open(dbPath: dbDir.path);
      addTearDown(second.dispose);

      // Read from the catalog on disk, not from the in-memory map `open()`
      // would have filled anyway.
      expect(await second.host.serverRegistry.documentCount, 1);
    });

    test('dispose() stops the host', () async {
      final example = await ExampleHost.open(dbPath: dbDir.path);
      await example.host.start();

      await example.dispose();

      expect(example.host.isRunning, isFalse);
    });
  });
}
