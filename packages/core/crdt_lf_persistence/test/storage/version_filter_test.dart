import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';
import 'package:test/test.dart';

void main() {
  late CRDTDocument document;
  late CRDTFugueTextHandler text;

  setUp(() {
    document = CRDTDocument(documentId: 'doc');
    text = CRDTFugueTextHandler(document, 'text');
  });

  /// Writes one change and returns everything written so far.
  List<Change> write(String value) {
    text.insert(text.length, value);
    return document.exportChanges();
  }

  group('filterByVersion', () {
    test('gives the list back untouched when neither bound is given', () {
      final changes = write('a');

      expect(
        identical(filterByVersion(changes), changes),
        isTrue,
        reason: 'a backend that asks for everything pays for nothing',
      );
    });

    test('newerThan keeps what the vector has not seen', () {
      write('a');
      final seen = document.getVersionVector();
      final all = write('b');

      final read = filterByVersion(all, newerThan: seen);

      expect(read, hasLength(1));
      expect(read.single.id, all.last.id);
    });

    test('upTo keeps what the vector has seen', () {
      final first = write('a');
      final seen = document.getVersionVector();
      final all = write('b');

      final read = filterByVersion(all, upTo: seen);

      expect(read.map((c) => c.id), first.map((c) => c.id));
    });

    test('the two together keep what sits between them', () {
      write('a');
      final start = document.getVersionVector();
      final middle = write('b').last;
      final end = document.getVersionVector();
      final all = write('c');

      final read = filterByVersion(all, newerThan: start, upTo: end);

      expect(read.single.id, middle.id);
    });

    test('a peer the vector never heard of is newer than it', () {
      final mine = write('a');
      final stranger = CRDTDocument(documentId: 'doc');
      CRDTFugueTextHandler(stranger, 'text').insert(0, 'theirs');
      final theirs = stranger.exportChanges();

      final read = filterByVersion(
        [...mine, ...theirs],
        newerThan: document.getVersionVector(),
      );

      expect(read.map((c) => c.id), theirs.map((c) => c.id));
    });
  });
}
