// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_quill/src/quill_converters.dart';
import 'package:flutter_quill/flutter_quill.dart' show Embeddable;
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('quillDeltaFromRichText', () {
    test('counts runes on the handler side, code units on the Quill side', () {
      final delta = quillDeltaFromRichText(
        RichTextDelta([
          RichTextRetain(1),
          RichTextRetain(1, {'bold': true}),
          RichTextInsert('x😀'),
          const RichTextDelete(1),
        ]),
        'a😀😀b\n',
      );

      expect(
        delta,
        Delta()
          ..retain(1)
          ..retain(2, {'bold': true})
          ..insert('x😀')
          ..delete(2),
      );
    });

    test('puts inline keys on text and block keys on newlines', () {
      final delta = quillDeltaFromRichText(
        RichTextDelta([
          RichTextRetain(5, {'bold': true, 'header': 1}),
          RichTextInsert('e\n', {'italic': true, 'list': 'bullet'}),
        ]),
        'ab\ncd\n',
      );

      expect(
        delta,
        Delta()
          ..retain(2, {'bold': true})
          ..retain(1, {'header': 1})
          ..retain(2, {'bold': true})
          ..insert('e', {'italic': true})
          ..insert('\n', {'list': 'bullet'}),
      );
    });

    test('keeps a null value as a removal', () {
      final delta = quillDeltaFromRichText(
        RichTextDelta([
          RichTextRetain(2, {'bold': null}),
        ]),
        'ab\n',
      );

      expect(delta, Delta()..retain(2, {'bold': null}));
    });
    test('an updated embed keeps the attributes it has in the document', () {
      final delta = quillDeltaFromRichText(
        RichTextDelta([
          RichTextRetain(1),
          RichTextUpdateEmbed(
            {'image': 'b.png'},
            {'italic': null, 'link': 'x'},
          ),
        ]),
        'a\uFFFC\n',
        document: Delta()
          ..insert('a')
          ..insert({'image': 'a.png'}, {'bold': true, 'italic': true})
          ..insert('\n'),
      );

      expect(
        delta,
        Delta()
          ..retain(1)
          ..insert({'image': 'b.png'}, {'bold': true, 'link': 'x'})
          ..delete(1),
      );
    });
  });

  group('richTextDeltaFromQuill', () {
    test('counts code units on the Quill side, runes on the handler side', () {
      final delta = richTextDeltaFromQuill(
        Delta()
          ..retain(3)
          ..insert('😀', {'bold': true})
          ..delete(2)
          ..retain(1, {'italic': null}),
        'a😀😀b\n',
      );

      expect(
        delta,
        RichTextDelta([
          RichTextRetain(2),
          RichTextInsert('😀', {'bold': true}),
          const RichTextDelete(1),
          RichTextRetain(1, {'italic': null}),
        ]),
      );
    });

    test('splits a retain at the newlines by scope', () {
      final delta = richTextDeltaFromQuill(
        Delta()..retain(4, {'bold': true, 'header': 2}),
        'ab\nc\n',
      );

      expect(
        delta,
        RichTextDelta([
          RichTextRetain(2, {'bold': true}),
          RichTextRetain(1, {'header': 2}),
          RichTextRetain(1, {'bold': true}),
        ]),
      );
    });

    test('drops a null value on an insert', () {
      expect(
        richTextDeltaFromQuill(Delta()..insert('a', {'bold': null}), '\n'),
        RichTextDelta([RichTextInsert('a')]),
      );
    });

    test('an embed that replaces an embed is an update, given the '
        'document', () {
      final document = Delta()
        ..insert('a')
        ..insert({'image': 'a.png'}, {'bold': true, 'italic': true})
        ..insert('\n');
      final change = Delta()
        ..retain(1)
        ..insert({'image': 'b.png'}, {'bold': true, 'link': 'x'})
        ..delete(1);

      expect(
        richTextDeltaFromQuill(change, 'a\uFFFC\n', document: document).ops,
        [
          RichTextRetain(1),
          RichTextUpdateEmbed(
            {'image': 'b.png'},
            {'link': 'x', 'italic': null},
          ),
        ],
      );
      expect(richTextDeltaFromQuill(change, 'a\uFFFC\n').ops, [
        RichTextRetain(1),
        RichTextInsertEmbed({'image': 'b.png'}, {'bold': true, 'link': 'x'}),
        const RichTextDelete(1),
      ]);
    });
  });

  group('quillDocumentFromSpans', () {
    test('adds the last newline to plain text', () {
      expect(quillDocumentFromSpans(const []), Delta()..insert('\n'));
      expect(
        quillDocumentFromSpans([
          RichTextSpan('a😀', {'bold': true}),
        ]),
        Delta()
          ..insert('a😀', {'bold': true})
          ..insert('\n'),
      );
      expect(
        quillDocumentFromSpans([RichTextSpan('a\n')]),
        Delta()..insert('a\n\n'),
      );
    });

    test('keeps a stored last newline as the last line', () {
      expect(
        quillDocumentFromSpans([
          RichTextSpan('Title'),
          RichTextSpan('\n', {'header': 1}),
        ]),
        Delta()
          ..insert('Title')
          ..insert('\n', {'header': 1}),
      );
      expect(
        quillDocumentFromSpans([
          RichTextSpan('Title'),
          RichTextSpan('\n', {'header': 1}),
          RichTextSpan('\n'),
        ]),
        Delta()
          ..insert('Title')
          ..insert('\n', {'header': 1})
          ..insert('\n'),
      );
    });

    test('drops inline keys on newlines and block keys on text', () {
      expect(
        quillDocumentFromSpans([
          RichTextSpan('a\nb', {'bold': true, 'list': 'bullet'}),
        ]),
        Delta()
          ..insert('a', {'bold': true})
          ..insert('\n', {'list': 'bullet'})
          ..insert('b', {'bold': true})
          ..insert('\n'),
      );
    });
  });

  test('an embed that is not one plain key is wrapped, and unwrapped back', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final nested = <String, Object?>{
      'a': [
        1,
        {'b': bytes},
      ],
    };
    for (final embed in <Map<String, Object?>>[
      {},
      {'image': 'a.png', 'alt': 'a'},
      {crdtQuillEmbedType: nested},
      {crdtQuillEmbedType: 'x'},
    ]) {
      final quill = quillEmbed(embed);
      expect(quill, {crdtQuillEmbedType: embed});
      expect(richTextEmbed(quill), embed);
      expect(richTextEmbed(Embeddable.fromJson(quill)), embed);
    }
    final plain = <String, Object?>{'image': nested};
    expect(quillEmbed(plain), plain);
    expect(richTextEmbed(quillEmbed(plain)), plain);
    expect(richTextEmbed({crdtQuillEmbedType: 'x'}), {crdtQuillEmbedType: 'x'});
  });
}
