// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

const _writer = RichTextWriter(expandOf: _expandOf, isBlockKey: _isBlockKey);

bool _isBlockKey(String key) => key == 'header';

MarkExpand _expandOf(String key) =>
    const {'link', 'header'}.contains(key) ? MarkExpand.none : MarkExpand.after;

void main() {
  late CRDTDocument document;
  late CRDTFugueRichTextHandler handler;

  void write(List<RichTextOp> ops) => document.runInTransaction(
        () => _writer.write(handler, RichTextDelta(ops)),
      );

  setUp(() {
    document = CRDTDocument(peerId: PeerId.generate());
    handler = CRDTFugueRichTextHandler(document, 'page');
    write([
      RichTextInsert('ab', {'bold': true}),
    ]);
  });

  tearDown(() => document.dispose());

  test('text inserted after bold takes exactly what was asked', () {
    write([
      RichTextRetain(2),
      RichTextInsert('c'),
      RichTextInsert('d', {'italic': true}),
    ]);

    expect(handler.value, [
      RichTextSpan('ab', {'bold': true}),
      RichTextSpan('c'),
      RichTextSpan('d', {'italic': true}),
    ]);
  });

  test('writes no mark when the inserted text already has the asked marks', () {
    final before = document.exportChanges().length;

    write([
      RichTextRetain(2),
      RichTextInsert('c', {'bold': true}),
    ]);

    expect(document.exportChanges().length, before + 1);
    expect(handler.value, [
      RichTextSpan('abc', {'bold': true}),
    ]);
  });

  test('a link does not grow, bold does', () {
    write([
      RichTextRetain(2, {'link': 'https://example.com'}),
    ]);
    handler.insert(2, 'c');

    expect(handler.attributesAt(2), {'bold': true});
  });

  test('a block key marks each newline on its own', () {
    write([
      RichTextRetain(2),
      RichTextInsert('\n\n', {'header': 1}),
    ]);
    handler.insert(3, 'x');

    expect(handler.attributesAt(2), {'header': 1});
    expect(handler.attributesAt(3), isNot(contains('header')));
    expect(handler.attributesAt(4), {'header': 1});
  });

  test(
      'an update on a rune that is not an embed puts the embed in its '
      'place', () {
    write([
      RichTextRetain(1),
      RichTextUpdateEmbed({'image': 'a.png'}, {'italic': true}),
    ]);

    expect(handler.value, [
      RichTextSpan('a', {'bold': true}),
      RichTextSpan.embed({'image': 'a.png'}, {'italic': true}),
    ]);
  });

  test('an embed takes exactly its attributes, and an update keeps it', () {
    write([
      RichTextRetain(2),
      RichTextInsertEmbed({'image': 'a.png'}, {'link': 'x'}),
    ]);
    write([
      RichTextRetain(2),
      RichTextUpdateEmbed({'image': 'b.png'}),
    ]);

    expect(handler.value, [
      RichTextSpan('ab', {'bold': true}),
      RichTextSpan.embed({'image': 'b.png'}, {'link': 'x'}),
    ]);
  });

  test('a block key on a retain marks each newline on its own', () {
    write([RichTextRetain(2), RichTextInsert('\n\n')]);
    write([
      RichTextRetain(2),
      RichTextRetain(2, {'header': 1}),
    ]);
    handler.insert(3, 'x');

    expect(handler.attributesAt(2)['header'], 1);
    expect(handler.attributesAt(3), isNot(contains('header')));
    expect(handler.attributesAt(4)['header'], 1);
  });

  test('typed text takes its left, and the asked attributes but on newlines',
      () {
    final inserted =
        _writer.insertTyped(handler, 2, 'c\nd', {'italic': true, 'link': 'x'});

    expect(inserted.map((op) => op.text).join(), 'c\nd');
    for (final index in [2, 4]) {
      expect(handler.attributesAt(index), {
        'bold': true,
        'italic': true,
        'link': 'x',
      });
    }
    expect(handler.attributesAt(3), isNot(contains('link')));
    handler.insert(5, 'e');
    expect(handler.attributesAt(5), {'bold': true, 'italic': true});
    expect(_writer.insertTyped(handler, 0, '', {'italic': true}), isEmpty);
  });

  test('a delete or a retain past the end is clamped', () {
    write([RichTextRetain(1), const RichTextDelete(5)]);
    write([
      RichTextRetain(3, {'italic': true}),
    ]);

    expect(handler.value, [
      RichTextSpan('a', {'bold': true, 'italic': true}),
    ]);
  });
}
