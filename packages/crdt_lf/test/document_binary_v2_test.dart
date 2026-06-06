import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
  group('CRDTDocument binary v2', () {
    test('export/import v2 syncs text changes', () {
      final doc1 = CRDTDocument(peerId: PeerId.generate());
      final doc2 = CRDTDocument(peerId: PeerId.generate());

      final t1 = CRDTTextHandler(doc1, 'text');
      final t2 = CRDTTextHandler(doc2, 'text');

      t1
        ..insert(0, 'Hello')
        ..insert(5, ' World');

      final bytes = doc1.binaryExportChanges();
      final applied = doc2.binaryImportChanges(Uint8List.fromList(bytes));
      expect(applied, greaterThan(0));

      expect(t2.value, equals(t1.value));
    });

    test('export/import v2 syncs multiple handler types together', () {
      final doc1 = CRDTDocument(peerId: PeerId.generate());
      final doc2 = CRDTDocument(peerId: PeerId.generate());

      final text1 = CRDTTextHandler(doc1, 'text');
      final fugue1 = CRDTFugueTextHandler(doc1, 'fugue');
      final list1 = CRDTListHandler<String>(doc1, 'list');
      final map1 = CRDTORMapHandler<String, int>(doc1, 'or_map');

      final text2 = CRDTTextHandler(doc2, 'text');
      final fugue2 = CRDTFugueTextHandler(doc2, 'fugue');
      final list2 = CRDTListHandler<String>(doc2, 'list');
      final map2 = CRDTORMapHandler<String, int>(doc2, 'or_map');

      text1.insert(0, 'plain');
      fugue1
        ..insert(0, 'fugue')
        ..delete(1, 2)
        ..insert(0, 'Z');
      list1
        ..insert(0, 'a')
        ..insert(1, 'b');
      map1
        ..put('count', 1)
        ..put('total', 99);

      final bytes = doc1.binaryExportChanges();
      doc2.binaryImportChanges(Uint8List.fromList(bytes));

      expect(text2.value, equals(text1.value));
      expect(fugue2.value, equals(fugue1.value));
      expect(list2.value, equals(list1.value));
      expect(map2.value, equals(map1.value));
    });
  });
}
