@TestOn('vm')
library;

import 'dart:io';

import 'package:crdt_lf_persistence/io.dart';
import 'package:persistence_conformance/persistence_conformance.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('crdt_lf_file_storage');
  });

  tearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  runDocumentStorageConformanceTests(
    name: 'FileDocumentStorage',
    open: (documentId) => FileDocumentStorage.open(
      '${directory.path}${Platform.pathSeparator}$documentId.crdt',
    ),
  );

  group('FileDocumentStorage', () {
    String pathFor(String name) =>
        '${directory.path}${Platform.pathSeparator}$name.crdt';

    test('a new file takes its name as the document id', () async {
      final storage = await FileDocumentStorage.open(pathFor('notes'));

      expect(storage.documentId, 'notes');
    });

    test('the id stored in the file wins over the one passed in', () async {
      final path = pathFor('notes');
      final first = await FileDocumentStorage.open(path, documentId: 'room-1');
      final fixtures = ConformanceFixtures('room-1');
      await first.changes.saveChanges(fixtures.changes(1));

      final second = await FileDocumentStorage.open(
        path,
        documentId: 'room-2',
      );

      expect(second.documentId, 'room-1');
    });

    test('nothing is written until something is stored', () async {
      final path = pathFor('notes');

      await FileDocumentStorage.open(path);

      expect(File(path).existsSync(), isFalse);
    });

    test('a file from a newer format is refused, not misread', () async {
      final path = pathFor('notes');
      final storage = await FileDocumentStorage.open(path);
      await storage.changes.saveChanges(
        ConformanceFixtures('notes').changes(1),
      );

      // The first byte is the format version.
      final bytes = File(path).readAsBytesSync();
      bytes[0] = 99;
      File(path).writeAsBytesSync(bytes);

      await expectLater(
        FileDocumentStorage.open(path),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('delete removes the file and what it held', () async {
      final path = pathFor('notes');
      final storage = await FileDocumentStorage.open(path);
      final fixtures = ConformanceFixtures('notes');
      await storage.changes.saveChanges(fixtures.changes(1));

      await storage.delete();

      expect(File(path).existsSync(), isFalse);
      expect(await storage.changes.getChanges(), isEmpty);
    });
  });
}
