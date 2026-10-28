// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_quill/crdt_lf_quill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CRDTDocument document;
  late CRDTFugueRichTextHandler handler;

  void write(List<RichTextOp> ops) => document.runInTransaction(
    () => writeRichTextDelta(handler, RichTextDelta(ops)),
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
