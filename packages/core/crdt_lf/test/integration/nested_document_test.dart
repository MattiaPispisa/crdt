import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

/// Integration test modelling a Google-Docs-like nested document:
/// root → chapters → chapter → blocks → (paragraph, table → rows → cells).
void main() {
  group('nested document (Google Docs-like)', () {
    test('concurrent row insert and cell edit converge', () {
      // --- Peer A builds the initial document. ---
      final docA = CRDTDocument()..registerDefaultFactories();
      final cell = CRDTFugueTextHandler(docA, 'r0c0')..insert(0, 'hi');
      final row0 = CRDTListRefHandler(docA, 'r0')..insertRef(0, cell);
      final table = CRDTListRefHandler(docA, 'table')..insertRef(0, row0);
      final paragraph = CRDTFugueTextHandler(docA, 'p0')..insert(0, 'para');
      final blocks = CRDTListRefHandler(docA, 'blocks')
        ..insertRef(0, paragraph)
        ..insertRef(1, table);
      final title = CRDTFugueTextHandler(docA, 'title')..insert(0, 'Title');
      final chapter = CRDTMapRefHandler(docA, 'ch0')
        ..setRef('title', title)
        ..setRef('blocks', blocks);
      final chapters = CRDTListRefHandler(docA, 'chapters')
        ..insertRef(0, chapter);
      final rootA = CRDTMapRefHandler(docA, 'root')
        ..setRef('chapters', chapters);

      // --- Peer B receives the document and rebuilds it. ---
      final docB = CRDTDocument()..registerDefaultFactories();
      final rootB = CRDTMapRefHandler(docB, 'root');
      docB
        ..importChanges(docA.exportChanges())
        ..reconstruct();

      // --- Concurrent edits. ---
      // A appends a new row (with one cell) to the table.
      final cellA = CRDTFugueTextHandler(docA, 'rAcA')..insert(0, 'X');
      final rowA = CRDTListRefHandler(docA, 'rA')..insertRef(0, cellA);
      table.insertRef(1, rowA);

      // B types into the existing cell: 'hi' -> 'hi!'.
      (docB.registeredHandlers['r0c0']! as CRDTFugueTextHandler).insert(2, '!');

      // --- Sync both ways. ---
      docA.importChanges(docB.exportChanges());
      docB.importChanges(docA.exportChanges());

      final expected = {
        'chapters': [
          {
            'title': 'Title',
            'blocks': [
              'para',
              [
                ['hi!'],
                ['X'],
              ],
            ],
          },
        ],
      };

      expect(rootA.resolved, expected);
      expect(rootB.resolved, expected);
    });
  });
}
