// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart' hide ChangeSource;
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_lf_quill/crdt_lf_quill.dart';
import 'package:crdt_lf_quill/src/crdt_quill_binding.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

final _peerA = PeerId.parse('00000000-0000-4000-8000-00000000000a');
final _peerB = PeerId.parse('00000000-0000-4000-8000-00000000000b');

Future<void> _pump() => Future<void>.delayed(Duration.zero);

class _Peer {
  _Peer(PeerId peerId) : document = CRDTDocument(peerId: peerId) {
    handler = CRDTFugueRichTextHandler(document, 'page');
    quill = CrdtQuillBinding(controller);
    binding = CrdtEditorBinding<List<RichTextSpan>, RichTextDelta>(
      onRemoteDelta: quill.onRemoteDelta,
      onReset: quill.onReset,
      verifyProjection: quill.verifyProjection,
    );
    quill.binding = binding;
    binding.attach(document, 'page');
  }

  final CRDTDocument document;
  late final CRDTFugueRichTextHandler handler;
  final QuillController controller = QuillController.basic();
  late final CrdtQuillBinding quill;
  late final CrdtEditorBinding<List<RichTextSpan>, RichTextDelta> binding;

  Delta get content => controller.document.toDelta();

  String get plain => controller.document.toPlainText();

  int get runes => plain.runes.length;

  // UTF-16 offset of the rune numbered [rune].
  int at(int rune) => RuneOffsets.utf16Offset(plain, rune);

  void type(int rune, String text) =>
      controller.replaceText(at(rune), 0, text, null);

  void delete(int rune, int count) =>
      controller.replaceText(at(rune), at(rune + count) - at(rune), '', null);

  void format(int rune, int count, Attribute<dynamic> attribute) =>
      controller.formatText(at(rune), at(rune + count) - at(rune), attribute);

  void dispose() {
    binding.dispose();
    quill.dispose();
    controller.dispose();
    document.dispose();
  }
}

void _sync(_Peer a, _Peer b) {
  b.document.importChanges(a.document.exportChanges());
  a.document.importChanges(b.document.exportChanges());
}

void _expectConverged(_Peer a, _Peer b, [String reason = '']) {
  expect(b.handler.value, a.handler.value, reason: reason);
  final expected = quillDocumentFromSpans(a.handler.value);
  expect(a.content, expected, reason: 'A $reason');
  expect(b.content, expected, reason: 'B $reason');
}

void main() {
  late _Peer a;
  late _Peer b;

  setUp(() async {
    a = _Peer(_peerA);
    b = _Peer(_peerB);
    await _pump();
  });

  tearDown(() {
    a.dispose();
    b.dispose();
  });

  test('a local edit reaches the other peer with its attributes', () {
    a
      ..type(0, 'hi 😀 there')
      ..format(0, 2, Attribute.bold);
    _sync(a, b);

    expect(
      b.content,
      Delta()
        ..insert('hi', {'bold': true})
        ..insert(' 😀 there\n'),
    );
    expect(b.handler.text, 'hi 😀 there');
  });

  test('text inserted after bold is plain when Quill says so', () {
    a
      ..type(0, 'ab')
      ..format(0, 2, Attribute.bold);
    a.controller.document.compose(
      Delta()
        ..retain(2)
        ..insert('c'),
      ChangeSource.local,
    );
    _sync(a, b);

    expect(a.handler.attributesAt(2), isEmpty);
    _expectConverged(a, b);
  });

  test('two empty documents do not double the last newline', () {
    a.type(0, 'a');
    b.type(0, 'b');
    _sync(a, b);

    expect(a.handler.length, 2);
    expect(a.plain, endsWith('\n'));
    expect(a.plain, isNot(endsWith('\n\n')));
    _expectConverged(a, b);
  });

  test('a heading on the last line and its change sync', () {
    a
      ..type(0, 'Title')
      ..format(5, 0, Attribute.h1);
    _sync(a, b);

    expect(
      b.content,
      Delta()
        ..insert('Title')
        ..insert('\n', {'header': 1}),
    );
    expect(a.handler.text, 'Title\n');

    a.format(5, 0, Attribute.h2);
    _sync(a, b);
    expect(
      b.content,
      Delta()
        ..insert('Title')
        ..insert('\n', {'header': 2}),
    );

    a.format(5, 0, Attribute.header);
    _sync(a, b);
    expect(b.content, Delta()..insert('Title\n'));
    expect(a.handler.text, 'Title');
  });

  test('an empty line after a last heading is kept', () {
    a
      ..type(0, 'Title')
      ..format(5, 0, Attribute.h1)
      ..type(5, '\n');
    _sync(a, b);
    _expectConverged(a, b);
    expect(b.plain, 'Title\n\n');

    b.type(6, 'x');
    _sync(a, b);
    _expectConverged(a, b);
    expect(a.plain, 'Title\nx\n');
  });

  test('a drifted editor is read again from the handler', () {
    debugVerifyCrdtQuillProjection = false;
    addTearDown(() => debugVerifyCrdtQuillProjection = true);
    a.type(0, 'hello');
    _sync(a, b);
    // Never pushed: the editor now shows text the handler does not have.
    a.controller.document.compose(Delta()..insert('zz'), ChangeSource.silent);

    b.type(0, '> ');
    _sync(a, b);

    expect(a.plain, '> hello\n');
    _expectConverged(a, b);
  });

  test('undo takes back only the local text, on both peers', () {
    a.type(0, 'aaa');
    _sync(a, b);
    b.type(3, 'bbb');
    _sync(a, b);

    a.controller.undo();
    _sync(a, b);

    expect(a.plain, 'bbb\n');
    _expectConverged(a, b);
  });

  test('a remote change is not undoable', () {
    b.type(0, 'remote');
    _sync(a, b);

    expect(a.controller.hasUndo, isFalse);
  });

  // More than one seed: one stream of random edits is one sample.
  for (final seed in [7, 13, 29, 101, 997]) {
    test('tracks a random stream of edits (seed $seed)', () {
      final random = Random(seed);
      String typed() => switch (random.nextInt(10)) {
        0 => '😀',
        1 => '\n',
        2 => 'x😀y',
        _ => String.fromCharCode(97 + random.nextInt(26)),
      };
      final inline = <Attribute<dynamic>>[
        Attribute.bold,
        Attribute.clone(Attribute.bold, null),
        Attribute.italic,
        Attribute.clone(Attribute.italic, null),
        const LinkAttribute('https://example.com'),
        const LinkAttribute(null),
      ];
      final block = <Attribute<dynamic>>[
        Attribute.h1,
        Attribute.h2,
        Attribute.header,
        Attribute.ul,
        Attribute.ol,
        Attribute.clone(Attribute.ul, null),
      ];

      for (var round = 0; round < 60; round++) {
        for (final peer in [a, b]) {
          for (var edit = random.nextInt(4); edit > 0; edit--) {
            // The last rune is Quill's own newline: edits stay before it.
            final length = peer.runes - 1;
            final index = random.nextInt(length + 1);
            final count = length == index
                ? 0
                : 1 + random.nextInt(min(4, length - index));
            // One undo step per edit: Quill merges the edits made within
            // 400 ms.
            peer.controller.document.history.lastRecorded = 0;
            switch (random.nextInt(10)) {
              case 0 || 1 || 2 || 3 || 4:
                peer.type(index, typed());
              case 5 when count > 0:
                peer.delete(index, count);
              case 6 || 7 when count > 0:
                peer.format(index, count, inline[random.nextInt(6)]);
              case 8:
                peer.format(index, 0, block[random.nextInt(6)]);
              case 9:
                peer.controller.undo();
            }
          }
        }
        _sync(a, b);
        _expectConverged(a, b, 'round $round');
      }
    });
  }
}
