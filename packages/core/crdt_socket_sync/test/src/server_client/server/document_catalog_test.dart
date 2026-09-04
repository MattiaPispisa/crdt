import 'package:crdt_socket_sync/src/server_client/server/document_catalog.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryServerDocumentCatalog', () {
    test('starts empty', () async {
      expect(await InMemoryServerDocumentCatalog().documentIds, isEmpty);
    });

    test('starts from the ids it was given', () async {
      final catalog = InMemoryServerDocumentCatalog(documentIds: {'a', 'b'});

      expect(await catalog.documentIds, {'a', 'b'});
    });

    test('adding the same id twice is not an error', () async {
      final catalog = InMemoryServerDocumentCatalog();

      await catalog.add('a');
      await catalog.add('a');

      expect(await catalog.documentIds, {'a'});
    });

    test('removing an id that is not there is not an error', () async {
      final catalog = InMemoryServerDocumentCatalog(documentIds: {'a'});

      await catalog.remove('b');

      expect(await catalog.documentIds, {'a'});
    });

    test('hands back a copy, so a caller cannot move what it holds', () async {
      final catalog = InMemoryServerDocumentCatalog(documentIds: {'a'});

      (await catalog.documentIds).add('b');

      expect(await catalog.documentIds, {'a'});
    });

    test('does not keep the set it was built from', () async {
      final seed = {'a'};
      final catalog = InMemoryServerDocumentCatalog(documentIds: seed);

      seed.add('b');

      expect(await catalog.documentIds, {'a'});
    });
  });
}
