import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

/// The spans of [handler] for [type], as `(start, end, value)` triples.
List<(int, int, Object)> _spans(CRDTRichTextHandler handler, String type) {
  return handler.value.spans
      .where((span) => span.type == type)
      .map((span) => (span.start, span.end, span.value))
      .toList();
}

void main() {
  group('CRDTRichTextHandler', () {
    late CRDTDocument doc;
    late CRDTRichTextHandler rich;

    setUp(() {
      doc = CRDTDocument();
      rich = CRDTRichTextHandler(doc, 'body');
    });

    test('is empty until written, then holds text and no formatting', () {
      expect(rich.value, const RichTextValue.empty());
      rich.insert(0, 'Hello');
      expect(rich.text, 'Hello');
      expect(rich.value.spans, isEmpty);
    });

    test('a mark covers exactly the range it was given', () {
      rich
        ..insert(0, 'abcde')
        ..addMark(start: 1, end: 3, type: 'bold', value: true);
      expect(_spans(rich, 'bold'), [(1, 3, true)]);
    });

    test('an empty or backwards range marks nothing', () {
      rich
        ..insert(0, 'abcde')
        ..addMark(start: 2, end: 2, type: 'bold', value: true)
        ..addMark(start: 3, end: 1, type: 'bold', value: true);
      expect(rich.value.spans, isEmpty);
    });

    test('toString shows the text and how many spans there are', () {
      rich
        ..insert(0, 'abc')
        ..addMark(start: 0, end: 2, type: 'bold', value: true);
      expect(rich.toString(), contains('CRDTRichText'));
      expect(rich.toString(), contains('1 spans'));
    });

    group('expansion', () {
      test('an expanding mark grows over text typed at either edge', () {
        rich
          ..insert(0, 'abcde')
          ..addMark(start: 2, end: 3, type: 'bold', value: true);
        expect(_spans(rich, 'bold'), [(2, 3, true)]);

        // Typed at the left edge of the range.
        rich.insert(2, 'X');
        expect(rich.text, 'abXcde');
        expect(_spans(rich, 'bold'), [(2, 4, true)]);

        // Typed at the right edge: bold now covers 'Xc', so the edge is 4.
        rich.insert(4, 'Y');
        expect(rich.text, 'abXcYde');
        expect(_spans(rich, 'bold'), [(2, 5, true)]);
      });

      test('a non-expanding mark keeps its size at both edges', () {
        rich
          ..insert(0, 'abcde')
          ..addMark(
            start: 2,
            end: 3,
            type: 'link',
            value: 'https://example.com',
            expand: false,
          );
        expect(_spans(rich, 'link'), [(2, 3, 'https://example.com')]);

        rich.insert(2, 'X');
        expect(rich.text, 'abXcde');
        expect(_spans(rich, 'link'), [(3, 4, 'https://example.com')]);

        rich.insert(4, 'Y');
        expect(rich.text, 'abXcYde');
        expect(_spans(rich, 'link'), [(3, 4, 'https://example.com')]);
      });

      test('a mark reaching the document edges grows with the text', () {
        rich
          ..insert(0, 'bc')
          ..addMark(start: 0, end: 2, type: 'bold', value: true)
          ..insert(0, 'a')
          ..insert(3, 'd');
        expect(rich.text, 'abcd');
        expect(_spans(rich, 'bold'), [(0, 4, true)]);
      });
    });

    group('removal', () {
      test('takes the mark off only the range it names', () {
        rich
          ..insert(0, 'abcdef')
          ..addMark(start: 0, end: 6, type: 'bold', value: true)
          ..removeMark(start: 2, end: 4, type: 'bold');
        expect(_spans(rich, 'bold'), [(0, 2, true), (4, 6, true)]);
      });

      test('a later mark wins over an earlier removal', () {
        rich
          ..insert(0, 'abcdef')
          ..removeMark(start: 0, end: 6, type: 'bold')
          ..addMark(start: 2, end: 4, type: 'bold', value: true);
        expect(_spans(rich, 'bold'), [(2, 4, true)]);
      });

      test('two values of one type do not overlap: the later one wins', () {
        rich
          ..insert(0, 'abcdef')
          ..addMark(start: 0, end: 4, type: 'colour', value: 'red')
          ..addMark(start: 2, end: 6, type: 'colour', value: 'blue');
        expect(
          _spans(rich, 'colour'),
          [(0, 2, 'red'), (2, 6, 'blue')],
        );
      });
    });

    group('anchors survive editing', () {
      test('a mark outlives deletion of the character it anchors to', () {
        rich
          ..insert(0, 'abcde')
          ..addMark(start: 1, end: 4, type: 'bold', value: true)
          // Takes out 'bcd', the whole marked range and both anchors with it.
          ..delete(1, 3);
        expect(rich.text, 'ae');
        expect(rich.value.spans, isEmpty);

        // The anchors resolve to where the characters used to be, so text
        // typed back into that spot takes the mark again.
        rich.insert(1, 'XY');
        expect(rich.text, 'aXYe');
        expect(_spans(rich, 'bold'), [(1, 3, true)]);
      });

      test('anchorAt and indexOfAnchor are inverses', () {
        rich.insert(0, 'abcde');
        for (var i = 0; i <= 5; i += 1) {
          for (final side in MarkSide.values) {
            expect(
              rich.indexOfAnchor(rich.anchorAt(i, side)),
              i,
              reason: 'boundary $i on ${side.name}',
            );
          }
        }
      });

      test('an anchor naming an unknown character resolves to null', () {
        rich.insert(0, 'abc');
        final other = CRDTDocument(peerId: PeerId.generate());
        final otherRich = CRDTRichTextHandler(other, 'body')..insert(0, 'zzz');
        expect(
          rich.indexOfAnchor(otherRich.anchorAt(1, MarkSide.after)),
          isNull,
        );
      });
    });

    group('across peers', () {
      test('two peers marking at once converge, and keep both marks', () {
        final a = CRDTDocument(peerId: PeerId.generate());
        final b = CRDTDocument(peerId: PeerId.generate());
        final richA = CRDTRichTextHandler(a, 'body')..insert(0, 'abcdef');
        final richB = CRDTRichTextHandler(b, 'body');
        // Shared history first, so both peers agree on the characters.
        b.importChanges(a.exportChanges());

        richA.addMark(start: 0, end: 3, type: 'bold', value: true);
        richB.addMark(start: 2, end: 5, type: 'italic', value: true);

        a.importChanges(b.exportChanges());
        b.importChanges(a.exportChanges());

        expect(richA.value, richB.value);
        expect(_spans(richA, 'bold'), [(0, 3, true)]);
        expect(_spans(richA, 'italic'), [(2, 5, true)]);
      });

      test('concurrent marks of one type converge on the same winner', () {
        final a = CRDTDocument(peerId: PeerId.generate());
        final b = CRDTDocument(peerId: PeerId.generate());
        final richA = CRDTRichTextHandler(a, 'body')..insert(0, 'abcdef');
        final richB = CRDTRichTextHandler(b, 'body');
        b.importChanges(a.exportChanges());

        richA.addMark(start: 0, end: 6, type: 'colour', value: 'red');
        richB.addMark(start: 0, end: 6, type: 'colour', value: 'blue');

        a.importChanges(b.exportChanges());
        b.importChanges(a.exportChanges());

        expect(richA.value, richB.value);
        expect(richA.value.spans, hasLength(1));
      });

      test('a mark applied while the range is being deleted converges', () {
        final a = CRDTDocument(peerId: PeerId.generate());
        final b = CRDTDocument(peerId: PeerId.generate());
        final richA = CRDTRichTextHandler(a, 'body')..insert(0, 'abcdef');
        final richB = CRDTRichTextHandler(b, 'body');
        b.importChanges(a.exportChanges());

        richA.addMark(start: 1, end: 4, type: 'bold', value: true);
        richB.delete(1, 3);

        a.importChanges(b.exportChanges());
        b.importChanges(a.exportChanges());

        expect(richA.value, richB.value);
        expect(richA.text, 'aef');
        expect(richA.value.spans, isEmpty);
      });
    });

    group('snapshot', () {
      test('text and marks come back from a snapshot', () {
        rich
          ..insert(0, 'abcdef')
          ..addMark(start: 1, end: 4, type: 'bold', value: true)
          ..addMark(
            start: 0,
            end: 2,
            type: 'link',
            value: 'https://example.com',
            expand: false,
          );
        final before = rich.value;

        final restored = CRDTDocument(peerId: PeerId.generate());
        final restoredRich = CRDTRichTextHandler(restored, 'body');
        expect(restored.importSnapshot(doc.takeSnapshot()), isTrue);
        expect(restoredRich.value, before);
      });

      test('a mark still expands after a snapshot round-trip', () {
        rich
          ..insert(0, 'abcde')
          ..addMark(start: 2, end: 3, type: 'bold', value: true);

        final restored = CRDTDocument(peerId: PeerId.generate());
        final restoredRich = CRDTRichTextHandler(restored, 'body');
        expect(restored.importSnapshot(doc.takeSnapshot()), isTrue);
        restoredRich.insert(3, 'X');
        expect(restoredRich.text, 'abcXde');
        expect(_spans(restoredRich, 'bold'), [(2, 4, true)]);
      });

      test('a document with no marks round-trips', () {
        rich.insert(0, 'plain');
        final restored = CRDTDocument(peerId: PeerId.generate());
        final restoredRich = CRDTRichTextHandler(restored, 'body');
        expect(restored.importSnapshot(doc.takeSnapshot()), isTrue);
        expect(restoredRich.text, 'plain');
        expect(restoredRich.value.spans, isEmpty);
      });
    });
  });
}
