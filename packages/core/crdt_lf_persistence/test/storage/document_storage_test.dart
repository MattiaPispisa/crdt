import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';
import 'package:persistence_conformance/persistence_conformance.dart';
import 'package:test/test.dart';

void main() {
  group('CRDTDocumentStorage', () {
    test('the two halves have to belong to the same document', () {
      expect(
        () => CRDTDocumentStorage(
          changes: InMemoryChangeStorage('doc'),
          snapshots: InMemorySnapshotStorage('other'),
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('close does nothing by default, twice included', () async {
      final storage = InMemoryDocumentStorage('doc');

      await storage.close();
      await storage.close();

      expect(storage.documentId, 'doc');
    });
  });
}
