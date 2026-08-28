import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/algorithm/fugue/tree.dart';
import 'package:crdt_lf/src/handler/fugue/fugue_delta.dart';
import 'package:test/test.dart';

/// The handlers guard these cases before they call, so a delta builder only
/// meets them when something upstream is wrong. It answers "nothing moved"
/// rather than reporting a move it cannot place.
void main() {
  final peer = PeerId.parse('00000000-0000-4000-8000-000000000001');

  group('fugueInsertDelta', () {
    test('reports nothing when there is nothing to insert', () {
      final delta = fugueInsertDelta<String>(
        FugueTree<String>.empty(),
        FugueElementID(peer, 0),
        [],
      );

      expect(delta.isEmpty, isTrue);
    });

    test('reports nothing for an id the tree does not know', () {
      final delta = fugueInsertDelta<String>(
        FugueTree<String>.empty(),
        FugueElementID(peer, 0),
        ['a'],
      );

      expect(delta.isEmpty, isTrue);
    });
  });

  group('fugueInsertAtDelta', () {
    test('reports nothing when there is nothing to insert', () {
      expect(fugueInsertAtDelta<String>(0, []).isEmpty, isTrue);
    });

    test('reports nothing for an offset outside the sequence', () {
      expect(fugueInsertAtDelta<String>(-1, ['a']).isEmpty, isTrue);
    });

    test('retains up to the offset before inserting', () {
      final delta = fugueInsertAtDelta<String>(2, ['a']);

      expect(delta.ops, [
        const SeqRetain<String>(2),
        const SeqInsert<String>(['a']),
      ]);
    });
  });
}
