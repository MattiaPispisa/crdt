import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

/// Integration test modelling a Figma/PowerPoint-like canvas:
/// slides (movable) → slide → element → (pos {x,y} as a LWW map, label text).
void main() {
  group('canvas (Figma-like)', () {
    CRDTDocument newDoc() => CRDTDocument()
      ..registerDefaultFactories()
      ..registerFactory('CRDTMapHandler<num>', CRDTMapHandler<num>.new);

    test('concurrent slide reorder and coordinate updates converge', () {
      // --- Peer A builds two slides, each with one positioned element. ---
      final docA = newDoc();

      final pos0 = CRDTMapHandler<num>(docA, 's0.pos')
        ..set('x', 0)
        ..set('y', 0);
      final label0 = CRDTFugueTextHandler(docA, 's0.label')..insert(0, 'A');
      final el0 = CRDTMapRefHandler(docA, 's0.el')
        ..setRef('pos', pos0)
        ..setRef('label', label0);
      final slide0 = CRDTMapRefHandler(docA, 's0')..setRef('el', el0);

      final pos1 = CRDTMapHandler<num>(docA, 's1.pos')
        ..set('x', 0)
        ..set('y', 0);
      final label1 = CRDTFugueTextHandler(docA, 's1.label')..insert(0, 'B');
      final el1 = CRDTMapRefHandler(docA, 's1.el')
        ..setRef('pos', pos1)
        ..setRef('label', label1);
      final slide1 = CRDTMapRefHandler(docA, 's1')..setRef('el', el1);

      final slidesA = CRDTMovableListRefHandler(docA, 'slides')
        ..insertRef(0, slide0)
        ..insertRef(1, slide1);

      // --- Peer B rebuilds the canvas. ---
      final docB = newDoc();
      final slidesB = CRDTMovableListRefHandler(docB, 'slides');
      docB
        ..importChanges(docA.exportChanges())
        ..reconstruct();

      // --- Concurrent edits. ---
      // A reorders the slides and moves element 0 along the y axis.
      slidesA.move(1, 0);
      pos0.set('y', 20);
      // B moves the same element along the x axis (different key, no loss).
      (docB.registeredHandlers['s0.pos']! as CRDTMapHandler<num>).set('x', 10);

      // --- Sync both ways. ---
      docA.importChanges(docB.exportChanges());
      docB.importChanges(docA.exportChanges());

      final expected = [
        {
          'el': {
            'pos': {'x': 0, 'y': 0},
            'label': 'B',
          },
        },
        {
          'el': {
            'pos': {'x': 10, 'y': 20},
            'label': 'A',
          },
        },
      ];

      expect(slidesA.resolved, expected);
      expect(slidesB.resolved, expected);
      expect(slidesA.resolved, slidesB.resolved);
    });
  });
}
