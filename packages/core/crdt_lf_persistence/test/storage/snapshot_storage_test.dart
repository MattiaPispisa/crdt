import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';
import 'package:persistence_conformance/persistence_conformance.dart';
import 'package:test/test.dart';

/// A document holding [text], snapshotted.
///
/// Two documents built this way have unrelated version vectors, which is what
/// the concurrent case needs.
Snapshot _snapshotOf(String documentId, String text) {
  final document = CRDTDocument(documentId: documentId);
  CRDTFugueTextHandler(document, 'body').insert(0, text);
  return document.takeSnapshot(pruneHistory: false);
}

void main() {
  group('newestSnapshot', () {
    test('answers null for nothing stored', () {
      expect(newestSnapshot([]), isNull);
    });

    test('picks the newest vector, not the last of the list', () {
      final document = CRDTDocument(documentId: 'doc');
      final text = CRDTFugueTextHandler(document, 'body')..insert(0, 'a');
      final older = document.takeSnapshot(pruneHistory: false);
      text.insert(1, 'b');
      final newer = document.takeSnapshot(pruneHistory: false);

      // Both orders: the answer must come from the vector, never the order the
      // backend returned its rows in.
      expect(newestSnapshot([older, newer]), same(newer));
      expect(newestSnapshot([newer, older]), same(newer));
    });

    test('picks the same one of two concurrent vectors either way', () {
      final left = _snapshotOf('left', 'a');
      final right = _snapshotOf('right', 'b');
      final expected = left.id.compareTo(right.id) <= 0 ? left : right;

      // Neither has seen the other, so the vector cannot choose. The id does,
      // and it has to choose the same one whatever order the rows came in:
      // no adapter orders them, so anything else restores a different
      // document per backend from the same bytes.
      expect(newestSnapshot([left, right]), same(expected));
      expect(newestSnapshot([right, left]), same(expected));
    });
  });

  group('getLatestSnapshot', () {
    test('reads the store and picks the newest', () async {
      final storage = InMemorySnapshotStorage('doc');
      final document = CRDTDocument(documentId: 'doc');
      final text = CRDTFugueTextHandler(document, 'body')..insert(0, 'a');
      final older = document.takeSnapshot(pruneHistory: false);
      text.insert(1, 'b');
      final newer = document.takeSnapshot(pruneHistory: false);

      // Written newest first, so a backend answering in insertion order would
      // hand back the older one.
      storage
        ..saveSnapshot(newer)
        ..saveSnapshot(older);

      expect(await storage.getLatestSnapshot(), same(newer));
    });

    test('answers null on an empty store', () async {
      expect(await InMemorySnapshotStorage('doc').getLatestSnapshot(), isNull);
    });
  });
}
