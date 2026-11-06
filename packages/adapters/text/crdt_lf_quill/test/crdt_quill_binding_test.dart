// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:math';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart' hide ChangeSource;
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_lf_quill/crdt_lf_quill.dart';
import 'package:crdt_lf_quill/src/crdt_quill_binding.dart';
import 'package:flutter/widgets.dart'
    show
        Builder,
        Column,
        ListenableBuilder,
        SizedBox,
        TextSelection,
        WidgetsBinding;
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

final _peerA = PeerId.parse('00000000-0000-4000-8000-00000000000a');
final _peerB = PeerId.parse('00000000-0000-4000-8000-00000000000b');

Future<void> _pump() => Future<void>.delayed(Duration.zero);

class _Peer {
  _Peer(PeerId peerId, {bool undo = false})
    : document = CRDTDocument(peerId: peerId) {
    handler = CRDTFugueRichTextHandler(document, 'page');
    if (undo) {
      manager = CRDTUndoManager(document, trackedOrigins: {crdtQuillOrigin})
        ..track(handler);
    }
    quill = CrdtQuillBinding(controller, undoManager: manager)..bind();
    binding = CrdtEditorBinding<List<RichTextSpan>, RichTextDelta>(
      onRemoteDelta: quill.onRemoteDelta,
      onReset: (spans, cause) {
        resets.add(cause);
        quill.onReset(spans, cause);
      },
      verifyProjection: quill.verifyProjection,
    );
    quill.binding = binding;
    binding.attach(document, 'page');
  }

  final CRDTDocument document;
  late final CRDTFugueRichTextHandler handler;
  CRDTUndoManager? manager;
  final QuillController controller = QuillController.basic();
  late final CrdtQuillBinding quill;
  late final CrdtEditorBinding<List<RichTextSpan>, RichTextDelta> binding;
  final List<ResetCause> resets = [];

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
    manager?.dispose();
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

  test('takes in a write made by a watcher inside a push', () async {
    debugVerifyCrdtQuillProjection = false;
    addTearDown(() => debugVerifyCrdtQuillProjection = true);
    a.type(0, 'hello');
    a.handler.insertEmbed(0, {'type': 'image', 'src': 'a.png'});
    final writes = <void Function()>[
      () => a.handler.format(1, 2, 'bold', true),
      () => a.handler.update(2, 'E'),
      () => a.handler.updateEmbed(0, {'type': 'image', 'src': 'b.png'}),
    ];
    // Listens before the binding, so it writes while the push runs.
    a.binding.detach();
    var armed = false;
    final watcher = a.handler.watch().listen((_) {
      if (armed) {
        armed = false;
        writes.removeAt(0)();
      }
    });
    addTearDown(watcher.cancel);
    a.binding.attach(a.document, 'page');
    await _pump();

    // One write per push.
    while (writes.isNotEmpty) {
      armed = true;
      a.type(a.runes - 1, 'X');
      expect(a.content, quillDocumentFromSpans(a.handler.value));
    }
    expect(a.content.first.data, {'image': 'b.png'});
  });

  test('an editor that drifted only in its attributes is read again', () {
    a.type(0, 'hello');
    _sync(a, b);
    a.controller.document.compose(
      Delta()..retain(5, {'bold': true}),
      ChangeSource.silent,
    );

    b.type(0, '> ');
    _sync(a, b);

    expect(a.content, quillDocumentFromSpans(a.handler.value));
    _expectConverged(a, b);
  });

  test('an inline embed and its data reach the other peer', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    a.type(0, 'ab');
    a.controller.replaceText(
      1,
      0,
      Embeddable('image', {'url': 'a.png', 'bytes': bytes}),
      null,
    );
    a.format(0, 3, Attribute.bold);
    _sync(a, b);

    expect(b.handler.text, 'a\uFFFCb');
    expect(b.handler.value[1].embed, {
      'image': {'url': 'a.png', 'bytes': bytes},
    });
    expect(
      b.content,
      Delta()
        ..insert('a', {'bold': true})
        ..insert(
          {
            'image': {'url': 'a.png', 'bytes': bytes},
          },
          {'bold': true},
        )
        ..insert('b', {'bold': true})
        ..insert('\n'),
    );
    expect(b.resets, [ResetCause.initial]);
    _expectConverged(a, b);
  });

  test('a block embed keeps its newline and its block attributes', () {
    a
      ..type(0, 'abc')
      ..type(1, 'x');
    a.controller.replaceText(1, 0, BlockEmbed.video('v.mp4'), null);
    // Quill puts the video on its own line, and adds one more newline.
    expect(a.plain, 'a\n\uFFFC\n\nxbc\n');
    a.format(3, 0, Attribute.centerAlignment);
    _sync(a, b);

    expect(a.handler.text, 'a\n\uFFFC\n\nxbc');
    expect(a.handler.attributesAt(3), {'align': 'center'});
    expect(b.content, a.content);
    expect(a.resets, [ResetCause.initial]);
    expect(b.resets, [ResetCause.initial]);
    _expectConverged(a, b);
  });

  test('an embed replaced in one change is updated, else deleted and '
      'inserted', () {
    a.type(0, 'ab');
    a.controller.replaceText(1, 0, BlockEmbed.image('a.png'), null);
    _sync(a, b);
    final deltas = <RichTextDelta>[];
    a.binding.detach();
    final watcher = a.handler.watch().listen((update) {
      if (update case HandlerDelta(:final delta)) {
        deltas.add(delta);
      }
    });
    addTearDown(watcher.cancel);
    a.binding.attach(a.document, 'page');

    return _pump().then((_) {
      a.controller.replaceText(1, 1, Delta()..insert({'image': 'b.png'}), null);
      expect(deltas, [
        RichTextDelta([
          RichTextRetain(1),
          RichTextUpdateEmbed({'type': 'image', 'src': 'b.png'}),
        ]),
      ]);
      _sync(a, b);
      expect(b.content.toList()[1].data, {'image': 'b.png'});

      deltas.clear();
      a.controller.replaceText(1, 1, BlockEmbed.image('c.png'), null);
      expect(deltas, [
        RichTextDelta([
          RichTextRetain(2),
          RichTextInsertEmbed({'type': 'image', 'src': 'c.png'}),
        ]),
        RichTextDelta([RichTextRetain(1), const RichTextDelete(1)]),
      ]);
      _sync(a, b);
      expect(b.content.toList()[1].data, {'image': 'c.png'});
      _expectConverged(a, b);
    });
  });

  test('an embed that replaces a letter in one change takes all its '
      'attributes', () {
    a
      ..type(0, 'ab')
      ..format(0, 2, Attribute.bold);
    a.controller.document.compose(
      Delta()
        ..retain(1)
        ..insert({'image': 'a.png'}, {'bold': true})
        ..delete(1),
      ChangeSource.local,
    );

    expect(a.handler.value, [
      RichTextSpan('a', {'bold': true}),
      RichTextSpan.embed({'type': 'image', 'src': 'a.png'}, {'bold': true}),
    ]);
    expect(a.resets, [ResetCause.initial]);
  });

  test('an embed that is not one plain key goes through Quill whole', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final embeds = <Map<String, Object?>>[
      {
        'image': 'a.png',
        'size': {
          'w': 2,
          'tags': [1, 'x', bytes],
        },
      },
      {},
      {
        crdtQuillEmbedType: {'image': 'b.png'},
      },
    ];
    a.type(0, 'ab');
    for (final embed in embeds.reversed) {
      a.handler.insertEmbed(1, embed);
    }
    expect(
      [for (final op in a.content.toList().sublist(1, 4)) op.data],
      [
        for (final embed in embeds) {crdtQuillEmbedType: embed},
      ],
    );

    // Quill to handler: the same embeds typed in the other editor.
    b.type(0, 'cd');
    for (final op in a.content.toList().sublist(1, 4).reversed) {
      b.controller.replaceText(
        1,
        0,
        Embeddable.fromJson(op.data! as Map<String, dynamic>),
        null,
      );
    }
    expect(
      [for (final span in b.handler.value) span.embed],
      [null, ...embeds, null],
    );

    _sync(a, b);
    a.type(0, '>');
    b.type(0, '<');
    _sync(a, b);
    _expectConverged(a, b);
    expect(a.resets, [ResetCause.initial]);
    expect(b.resets, [ResetCause.initial]);
  });

  test('a Quill update of a wrapped embed updates the map it wraps', () {
    a.handler.insertEmbed(0, {'image': 'a.png', 'alt': 'a'});
    final deltas = <RichTextDelta>[];
    a.binding.detach();
    final watcher = a.handler.watch().listen((update) {
      if (update case HandlerDelta(:final delta)) {
        deltas.add(delta);
      }
    });
    addTearDown(watcher.cancel);
    a.binding.attach(a.document, 'page');
    a.resets.clear();

    return _pump().then((_) {
      a.controller.replaceText(
        0,
        1,
        Delta()..insert({
          crdtQuillEmbedType: {'image': 'b.png', 'alt': 'b'},
        }),
        null,
      );
      expect(deltas, [
        RichTextDelta([
          RichTextUpdateEmbed({'image': 'b.png', 'alt': 'b'}),
        ]),
      ]);
      expect(a.resets, isEmpty);
      expect(a.content.first.data, {
        crdtQuillEmbedType: {'image': 'b.png', 'alt': 'b'},
      });
    });
  });

  test('a wrapped single key is kept by the editor, and not read again', () {
    a.type(0, 'ab');
    a.controller.replaceText(
      1,
      0,
      const Embeddable(crdtQuillEmbedType, {'image': 'a.png'}),
      null,
    );
    a.type(0, '>');

    expect(a.handler.value[1].embed, {'image': 'a.png'});
    expect(a.content.toList()[1].data, {
      crdtQuillEmbedType: {'image': 'a.png'},
    });
    expect(a.resets, [ResetCause.initial]);
  });

  test('a refused embed reaches onUnsupported, the rest of the paste is '
      'written', () {
    final seen = <Object?>[];
    final refused = <Object?>[];
    bool own(int index, int len, Object? data) {
      seen.add(data);
      return true;
    }

    final controller = QuillController.basic()..onReplaceText = own;
    addTearDown(controller.dispose);
    a.quill
      ..controller = controller
      ..onUnsupported = refused.add
      ..embedTypes = {'image'};
    expect(a.controller.onReplaceText, isNull);
    a.resets.clear();

    final video = BlockEmbed.video('v.mp4');
    controller
      ..replaceText(0, 0, 'ab', null)
      ..replaceText(1, 0, video, null)
      ..replaceText(
        1,
        0,
        Delta()
          ..insert('x')
          ..insert({'video': 'w.mp4'})
          ..insert('y\uFFFC')
          ..insert({'image': 'a.png'}),
        const TextSelection.collapsed(offset: 6),
      );

    expect(refused, [
      video,
      {'video': 'w.mp4'},
    ]);
    expect(seen, hasLength(2));
    expect(a.resets, isEmpty);
    expect(a.handler.text, 'axy\uFFFCb');
    expect(controller.selection, const TextSelection.collapsed(offset: 4));
    expect(
      controller.document.toDelta(),
      quillDocumentFromSpans(a.handler.value),
    );

    a.quill.dispose();
    expect(controller.onReplaceText, own);
  });

  test('a refused embed composed into the document is dropped, its text '
      'kept', () {
    final refused = <Object?>[];
    a.quill
      ..onUnsupported = refused.add
      ..embedTypes = {'image'};
    a.type(0, 'ab');
    a.controller.document.compose(
      Delta()
        ..retain(1)
        ..insert({'formula': 'x'})
        ..insert('c\uFFFC'),
      ChangeSource.local,
    );

    expect(refused, [
      {'formula': 'x'},
    ]);
    expect(a.handler.text, 'acb');
    expect(a.plain, 'acb\n');
    _sync(a, b);
    _expectConverged(a, b);
  });

  group('embed data the handler refuses reaches onUnsupported', () {
    Object? nested(int depth) => depth == 0 ? 1 : [nested(depth - 1)];
    final cases = <String, Map<String, Object?>>{
      'above maxEmbedBytes': {'image': 'x' * 32},
      'nested too deep': {'image': nested(16)},
    };

    for (final MapEntry(key: name, value: embed) in cases.entries) {
      test('$name: the text of a paste is written', () {
        final refused = <Object?>[];
        a.quill.onUnsupported = refused.add;
        a.handler.maxEmbedBytes = 16;
        a.type(0, 'ab');
        a.controller.replaceText(
          1,
          0,
          Delta()
            ..insert('x')
            ..insert(embed)
            ..insert('y'),
          null,
        );

        expect(refused, [embed]);
        expect(a.handler.text, 'axyb');
        expect(a.plain, 'axyb\n');
        expect(
          a.controller.selection,
          const TextSelection.collapsed(offset: 3),
        );

        final key = embed.keys.single;
        final embeddable = Embeddable(key, embed[key]);
        a.controller.replaceText(1, 0, embeddable, null);
        expect(refused, [embed, embeddable]);
        expect(a.handler.text, 'axyb');
        expect(a.resets, [ResetCause.initial]);
      });
    }

    for (final (cause, type, value) in [
      ('embedTypes', 'formula', 'x' as Object),
      ('checkEmbed', 'image', 'x' * 64),
    ]) {
      group('$cause: an embed replaced by refused data stays', () {
        final image = {'type': 'image', 'src': 'a.png'};
        late List<Object?> refused;

        setUp(() {
          refused = [];
          a.quill
            ..onUnsupported = refused.add
            ..embedTypes = {'image'};
          a.handler.maxEmbedBytes = 32;
          a.type(0, 'ab');
          a.controller
            ..replaceText(1, 0, BlockEmbed.image('a.png'), null)
            ..updateSelection(
              const TextSelection.collapsed(offset: 3),
              ChangeSource.local,
            );
        });

        void expectKept(String text) {
          expect(a.handler.text, text);
          expect(
            [
              for (final span in a.handler.value)
                if (span.embed != null) span.embed,
            ],
            [image],
          );
          expect(a.content, quillDocumentFromSpans(a.handler.value));
        }

        test('in one change', () {
          a.controller.replaceText(1, 1, Delta()..insert({type: value}), null);
          expect(refused, [
            {type: value},
          ]);
          expectKept('a\uFFFCb');
          // Nothing is written: the caret stays.
          expect(
            a.controller.selection,
            const TextSelection.collapsed(offset: 3),
          );
          expect(a.resets, [ResetCause.initial]);
        });

        test('as an Embeddable', () {
          final embeddable = Embeddable(type, value);
          a.controller.replaceText(1, 1, embeddable, null);
          expect(refused, [embeddable]);
          expectKept('a\uFFFCb');
          expect(
            a.controller.selection,
            const TextSelection.collapsed(offset: 3),
          );
        });

        test('and the rest of the change is written', () {
          a.controller.replaceText(
            0,
            3,
            Delta()
              ..insert({type: value})
              ..insert('x'),
            null,
          );
          expect(refused, hasLength(1));
          expectKept('x\uFFFC');
          // After the written text, before the kept embed.
          expect(
            a.controller.selection,
            const TextSelection.collapsed(offset: 1),
          );
          expect(a.resets, [ResetCause.initial]);
        });

        test('when composed into the document', () {
          a.controller.document.compose(
            Delta()
              ..retain(1)
              ..insert({type: value})
              ..delete(1),
            ChangeSource.local,
          );
          expect(refused, hasLength(1));
          expectKept('a\uFFFCb');
        });
      });
    }
  });

  test('an editor that drifted only in an embed is read again', () {
    a.controller.replaceText(0, 0, BlockEmbed.image('a.png'), null);
    _sync(a, b);
    a.controller.document.compose(
      Delta()
        ..insert({'image': 'b.png'})
        ..delete(1),
      ChangeSource.silent,
    );

    b.type(1, '!');
    _sync(a, b);

    expect(a.content.first.data, {'image': 'a.png'});
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

  test('a local edit made while a burst is still in flight converges', () {
    // The length check alone: only the read after the push brings in the
    // attributes still in flight.
    debugVerifyCrdtQuillProjection = false;
    addTearDown(() => debugVerifyCrdtQuillProjection = true);
    a.type(0, 'hello');
    _sync(a, b);
    a
      ..type(0, 'A')
      ..format(0, 3, Attribute.bold)
      ..format(3, 2, const LinkAttribute('https://example.com'));

    var armed = true;
    void typeInBurst() {
      if (!armed) {
        return;
      }
      armed = false;
      b
        ..type(1, 'z')
        ..format(0, 2, Attribute.italic);
    }

    b.controller.addListener(typeInBurst);
    b.resets.clear();
    b.document.importChanges(a.document.exportChanges());
    b.controller.removeListener(typeInBurst);

    expect(armed, isFalse);
    expect(b.resets, contains(ResetCause.deltasMissed));
    expect(b.content, quillDocumentFromSpans(b.handler.value));
    _sync(a, b);
    _expectConverged(a, b);
    expect(a.handler.text, contains('z'));
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
        // A reset would hide a wrong write: it reads the handler back.
        expect(a.resets, [ResetCause.initial], reason: 'A round $round');
        expect(b.resets, [ResetCause.initial], reason: 'B round $round');
      }
    });
  }

  testWidgets('a reset put off to the end of the frame leaves a new '
      'controller alone until then', (tester) async {
    final other = QuillController.basic();
    addTearDown(other.dispose);
    final c = _Peer(PeerId.generate());
    addTearDown(c.dispose);
    c.handler.insert(0, 'hi');
    await tester.pumpWidget(
      Column(
        children: [
          ListenableBuilder(
            listenable: other,
            builder: (context, _) => const SizedBox(),
          ),
          Builder(
            builder: (context) {
              c.binding.resync(ResetCause.initial);
              c.quill.controller = other;
              return const SizedBox();
            },
          ),
        ],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(other.document.toPlainText(), 'hi\n');
  });

  group('media', () {
    final src = Uri.parse('https://example.com/cat.png');

    test('an image with every field reaches another peer and a snapshot '
        'whole', () async {
      a.type(0, 'ab');
      a.handler.insertImage(
        1,
        src,
        alt: 'A cat',
        width: 640,
        height: 480,
        mime: 'image/png',
        displayWidth: 320,
      );
      _sync(a, b);
      final c = _Peer(PeerId.parse('00000000-0000-4000-8000-0000000000c3'));
      addTearDown(c.dispose);
      await _pump();
      expect(c.document.importSnapshot(a.document.takeSnapshot()), isTrue);

      final image = a.handler.value[1].image!;
      for (final (name, peer) in [('B', b), ('C', c)]) {
        final span = peer.handler.value[1];
        expect(span.image, image, reason: name);
        expect(span.displayWidth, 320, reason: name);
        final op = peer.content.toList()[1];
        expect(op.data, {crdtQuillEmbedType: image.toEmbed()}, reason: name);
        expect(op.attributes, {'style': 'width: 320'}, reason: name);
        expect(peer.quill.verifyProjection(), isTrue, reason: name);
      }
      expect(a.resets, [ResetCause.initial]);
      expect(b.resets, [ResetCause.initial]);
    });

    test('a Quill resize is the display width, and the rest of its style '
        'reaches the other Quill unchanged', () {
      a.type(0, 'ab');
      a.controller.replaceText(1, 0, BlockEmbed.image('$src'), null);
      _sync(a, b);
      expect(b.content.toList()[1].data, {'image': '$src'});
      // As the image menu of flutter_quill_extensions writes it.
      a.controller.formatText(
        1,
        1,
        const StyleAttribute(
          'width: 300.0; height: 200.0; alignment: topLeft; ',
        ),
      );
      _sync(a, b);

      final span = a.handler.value[1];
      expect(span.image?.src, src);
      expect(span.displayWidth, 300);
      expect(b.handler.value, a.handler.value);
      expect(b.content.toList()[1].attributes, {
        'style': 'width: 300; height: 200.0; alignment: topLeft',
      });

      // A width from the handler keeps the rest of the style Quill wrote.
      b.handler.format(1, 1, richTextDisplayWidthKey, 150);
      _sync(a, b);
      expect(a.content.toList()[1].attributes, {
        'style': 'width: 150; height: 200.0; alignment: topLeft',
      });
      expect(a.resets, [ResetCause.initial]);
      expect(b.resets, [ResetCause.initial]);
    });

    test('a block image keeps its alignment on its newline', () {
      a.handler.insertImage(
        0,
        src,
        block: true,
        attributes: {'align': 'center'},
      );
      _sync(a, b);

      expect(
        b.content,
        Delta()
          ..insert({'image': '$src'})
          ..insert('\n', {'align': 'center'}),
      );
      expect(b.resets, [ResetCause.initial]);
      _expectConverged(a, b);
    });

    test('embedTypes checks the type of a wrapped embed', () {
      final refused = <Object?>[];
      a.quill
        ..onUnsupported = refused.add
        ..embedTypes = {'image'};
      final image = {
        crdtQuillEmbedType: {'type': 'image', 'src': 'a.png', 'alt': 'a'},
      };
      final video = {
        crdtQuillEmbedType: {'type': 'video', 'src': 'v.mp4', 'title': 'v'},
      };
      a.controller.replaceText(
        0,
        0,
        Delta()
          ..insert(image)
          ..insert(video),
        null,
      );

      expect(refused, [video]);
      expect(a.handler.value.single.image?.alt, 'a');
    });
  });

  void select(_Peer peer, int offset) => peer.controller.updateSelection(
    TextSelection.collapsed(offset: offset),
    ChangeSource.local,
  );

  group('a change that splits a surrogate pair', () {
    setUp(() {
      debugVerifyCrdtQuillProjection = false;
      addTearDown(() => debugVerifyCrdtQuillProjection = true);
    });

    void expectShown(String text) {
      expect(a.handler.text, text);
      expect(a.plain, '$text\n');
      _sync(a, b);
      _expectConverged(a, b);
    }

    test('a replaced low half is the whole emoji, as the diff of the input '
        'gives it', () {
      a.type(0, '😀');
      a.controller.replaceText(1, 1, '\uDE01', null);

      expectShown('😁');
      expect(a.resets, [ResetCause.initial]);
      expect(a.controller.selection, const TextSelection.collapsed(offset: 2));
    });

    test('a replaced high half is the whole emoji', () {
      a.type(0, '😀');
      a.controller.replaceText(0, 1, '\uD83C', null);

      expectShown('\u{1F200}');
      expect(a.resets, [ResetCause.initial]);
    });

    test('text over one half replaces the whole emoji', () {
      a.type(0, 'x😀y');
      a.controller.replaceText(2, 1, 'z', null);
      expectShown('xzy');

      a.type(1, '😀');
      a.controller.replaceText(2, 1, 'w', null);
      expectShown('xwzy');
      expect(a.controller.selection, const TextSelection.collapsed(offset: 2));
    });

    test('a deleted half deletes the emoji and nothing else', () {
      a.type(0, 'x😀y');
      a.controller.replaceText(2, 1, '', null);
      expectShown('xy');
      expect(a.controller.selection, const TextSelection.collapsed(offset: 1));

      a.type(1, '😀');
      a.controller.replaceText(1, 1, '', null);
      expectShown('xy');
    });

    test('an insert inside a pair goes before the emoji', () {
      a.type(0, '😀');
      a.controller.replaceText(1, 0, 'z', null);

      expectShown('z😀');
      expect(a.controller.selection, const TextSelection.collapsed(offset: 1));
    });

    test('a Quill rule that deletes half an emoji deletes the emoji', () {
      a.type(0, '😀');
      a.controller.replaceText(2, 0, BlockEmbed.image('a.png'), null);
      a.type(2, '😀a');
      a.controller.replaceText(6, 0, BlockEmbed.image('b.png'), null);
      a.controller.replaceText(3, 2, '', null);

      expectShown('😀￼a￼');
    });

    test('a half composed away deletes the emoji', () {
      a.type(0, 'x😀y');
      a.controller.document.compose(
        Delta()
          ..retain(2)
          ..delete(1),
        ChangeSource.local,
      );

      expectShown('xy');
    });

    test('a lone half stays in the handler', () {
      a.type(0, 'ab');
      a.controller.replaceText(1, 0, '\uD83D', null);
      a.controller.replaceText(2, 0, 'c', null);

      expect(a.handler.length, 4);
      expect(a.handler.text, 'a\uD83Dcb');
      expect(a.plain, 'a\uD83Dcb\n');
      expect(a.resets, [ResetCause.initial]);
    });
  });

  group('a video from a peer', () {
    final video = Uri.parse('https://example.com/v.mp4');

    test('moves the Quill undo stack by one position', () {
      a.type(0, 'abcdef');
      a.controller.document.history.lastRecorded = 0;
      a.type(6, 'X');
      _sync(a, b);
      b.handler.insertVideo(2, video, block: false);
      _sync(a, b);

      a.controller.undo();

      expect(a.plain, 'ab￼cdef\n');
      _sync(a, b);
      _expectConverged(a, b);
    });

    test('moves the caret by the positions it takes', () {
      a.type(0, 'abcdef');
      _sync(a, b);
      select(a, 5);

      b.handler.insertVideo(2, video, block: false);
      _sync(a, b);
      expect(a.controller.selection, const TextSelection.collapsed(offset: 6));

      b.handler.insertVideo(2, video);
      _sync(a, b);
      expect(a.controller.selection, const TextSelection.collapsed(offset: 8));
      _expectConverged(a, b);
    });
  });

  group('a refusal deletes nothing', () {
    final refusedEmbed = Delta()..insert({'nope': 'x'});
    late List<Object?> refused;

    setUp(() {
      refused = [];
      a.quill
        ..onUnsupported = refused.add
        ..embedTypes = {'image'};
    });

    void fill(String text) {
      for (var i = text.length - 1; i >= 0; i--) {
        if (text[i] == '#') {
          a.controller.replaceText(0, 0, BlockEmbed.image('$i.png'), null);
        } else {
          a.controller.replaceText(0, 0, text[i], null);
        }
      }
    }

    String shown() => a.plain.replaceAll('￼', '#');

    for (final (name, data) in [
      ('an Embeddable', const Embeddable('nope', 'x') as Object),
      ('a delta', refusedEmbed),
    ]) {
      test('$name alone over text and embeds drops the whole replace', () {
        fill('a##b');
        select(a, 3);
        a.controller.replaceText(0, 2, data, null);

        expect(refused, hasLength(1));
        expect(shown(), 'a##b\n');
        expect(a.handler.length, 4);
        expect(
          a.controller.selection,
          const TextSelection.collapsed(offset: 3),
        );
      });
    }

    test('text over embeds keeps every embed', () {
      fill('a##b');
      a.controller.replaceText(
        0,
        4,
        Delta()
          ..insert({'nope': 'x'})
          ..insert('t'),
        null,
      );

      expect(shown(), 't##\n');
      expect(a.handler.length, 3);
      expect(a.controller.selection, const TextSelection.collapsed(offset: 1));
      expect(a.resets, [ResetCause.initial]);
    });

    test('a refused embed before the written text keeps the embed', () {
      fill('#');
      a.controller.replaceText(
        0,
        1,
        Delta()
          ..insert({'nope': 'x'})
          ..insert('t'),
        null,
      );

      expect(shown(), 't#\n');
    });

    test('an accepted embed counts as written', () {
      fill('ab');
      a.controller.replaceText(
        0,
        2,
        Delta()
          ..insert({'nope': 'x'})
          ..insert({'image': 'c.png'}),
        null,
      );
      expect(shown(), '#\n');

      fill('de');
      a.controller.document.compose(
        Delta()
          ..insert({'nope': 'y'})
          ..insert({'image': 'f.png'})
          ..delete(2),
        ChangeSource.local,
      );
      expect(shown(), '##\n');
      expect(a.handler.length, 2);
    });

    test('composed into the document, in the release build too', () {
      debugVerifyCrdtQuillProjection = false;
      addTearDown(() => debugVerifyCrdtQuillProjection = true);
      fill('a#b#c');
      a.controller.document.compose(
        Delta()
          ..insert({'nope': 'x'})
          ..delete(2)
          ..retain(1)
          ..insert('t')
          ..insert({'nope': 'y'})
          ..delete(2),
        ChangeSource.local,
      );

      expect(refused, hasLength(2));
      expect(a.handler.text, 'a￼bt￼');
      expect(shown(), 'a#bt#\n');
    });
  });

  for (final (key, value) in [
    ('bold', true as Object),
    ('link', 'https://a.example'),
  ]) {
    test('a clear of $key, which the insert sets, is foreign', () async {
      debugVerifyCrdtQuillProjection = false;
      addTearDown(() => debugVerifyCrdtQuillProjection = true);
      a.binding.detach();
      var armed = false;
      final watcher = a.handler.watch().listen((_) {
        if (armed) {
          armed = false;
          a.handler.format(0, 1, key, null, expand: MarkExpand.none);
        }
      });
      addTearDown(watcher.cancel);
      a.binding.attach(a.document, 'page');
      await _pump();

      armed = true;
      a.controller.replaceText(0, 0, Delta()..insert('x', {key: value}), null);

      expect(a.handler.attributesAt(0), isEmpty);
      expect(a.content, quillDocumentFromSpans(a.handler.value));
    });
  }

  test('text with its own link inside another link is read as an echo', () {
    a
      ..type(0, 'ab')
      ..format(0, 2, const LinkAttribute('https://a.example'));
    a.controller.replaceText(
      1,
      0,
      Delta()..insert('x', {'link': 'https://b.example'}),
      null,
    );

    expect(a.resets, [ResetCause.initial]);
    expect(a.content, quillDocumentFromSpans(a.handler.value));
  });

  test(
    'a manager set and removed later leaves no step of the Quill history',
    () {
      a.type(0, 'abcdef');
      a.quill.undoManager = a.manager = CRDTUndoManager(
        a.document,
        trackedOrigins: {crdtQuillOrigin},
      )..track(a.handler);
      a.delete(0, 6);
      a.quill.undoManager = null;

      expect(a.controller.hasUndo, isFalse);
      a.controller.undo();
      expect(a.handler.text, '');
    },
  );

  test('setting the same manager keeps the Quill history', () {
    a.type(0, 'ab');
    a.quill.undoManager = null;

    expect(a.controller.hasUndo, isTrue);
  });

  test('an attribute value the handler refuses reaches onUnsupported, the '
      'rest is written', () {
    final refused = <Object?>[];
    a.quill.onUnsupported = refused.add;
    a.type(0, 'ab');
    a.controller.replaceText(
      2,
      0,
      Delta()
        ..insert('c', {
          'x': [1],
          'bold': true,
        })
        ..insert('d'),
      null,
    );

    expect(refused, [
      {
        'x': [1],
      },
    ]);
    expect(a.handler.text, 'abcd');
    expect(a.handler.attributesAt(2), {'bold': true});
    expect(a.content, quillDocumentFromSpans(a.handler.value));
    expect(a.controller.selection, const TextSelection.collapsed(offset: 4));
    expect(a.resets, [ResetCause.initial]);
  });

  test('an attribute value composed into the document is taken out of the '
      'editor', () {
    debugVerifyCrdtQuillProjection = false;
    addTearDown(() => debugVerifyCrdtQuillProjection = true);
    final refused = <Object?>[];
    a.quill.onUnsupported = refused.add;
    a.type(0, 'ab');
    a.controller.document.compose(
      Delta()..retain(1, {
        'x': [1],
      }),
      ChangeSource.local,
    );

    expect(refused, hasLength(1));
    expect(a.handler.attributesAt(0), isEmpty);
    expect(a.content, Delta()..insert('ab\n'));
  });

  test('a resize stays off the text a peer types next to the image', () {
    a.type(0, 'ab');
    a.controller.replaceText(1, 0, BlockEmbed.image('a.png'), null);
    _sync(a, b);

    a.controller.formatText(1, 1, const StyleAttribute('width: 300'));
    b.type(2, 'x');
    _sync(a, b);

    expect(a.handler.attributesAt(2), isEmpty);
    _expectConverged(a, b);
  });

  test('an embed with a key that is not a String reaches onUnsupported', () {
    final refused = <Object?>[];
    a.quill.onUnsupported = refused.add;
    const embed = Embeddable(crdtQuillEmbedType, {1: 2});
    a.controller.replaceText(0, 0, embed, null);

    expect(refused, [embed]);
    expect(a.handler.text, '');
  });

  testWidgets('a reset in a build keeps the document, its selection and its '
      'undo stack', (tester) async {
    final c = _Peer(PeerId.parse('00000000-0000-4000-8000-0000000000d1'));
    addTearDown(c.dispose);
    c.type(0, 'hello');
    select(c, 3);
    // Never pushed: the reset has something to take back.
    final document = c.controller.document
      ..compose(
        Delta()
          ..retain(5)
          ..insert('!'),
        ChangeSource.silent,
      );

    await tester.pumpWidget(
      Builder(
        builder: (context) {
          c.binding.resync(ResetCause.deltasMissed);
          return const SizedBox();
        },
      ),
    );

    expect(c.controller.document, same(document));
    expect(c.plain, 'hello\n');
    expect(c.controller.selection, const TextSelection.collapsed(offset: 3));
    expect(c.controller.hasUndo, isTrue);
  });

  testWidgets(
    'a reset for another handler, in a build, starts a new document',
    (tester) async {
      final c = _Peer(PeerId.parse('00000000-0000-4000-8000-0000000000d4'));
      addTearDown(c.dispose);
      c.type(0, 'hello');
      select(c, 3);

      await tester.pumpWidget(
        Builder(
          builder: (context) {
            c.binding.resync(ResetCause.initial);
            return const SizedBox();
          },
        ),
      );

      expect(c.plain, 'hello\n');
      expect(c.controller.selection, const TextSelection.collapsed(offset: 0));
      expect(c.controller.hasUndo, isFalse);
    },
  );

  testWidgets('an edit made while a reset waits for the end of the frame is '
      'written', (tester) async {
    final c = _Peer(PeerId.parse('00000000-0000-4000-8000-0000000000d2'));
    addTearDown(c.dispose);
    c.type(0, 'hello');

    await tester.pumpWidget(
      Builder(
        builder: (context) {
          WidgetsBinding.instance.addPostFrameCallback((_) => c.type(5, '!'));
          c.binding.resync(ResetCause.deltasMissed);
          return const SizedBox();
        },
      ),
    );

    expect(c.handler.text, 'hello!');
    expect(c.plain, 'hello!\n');
  });

  testWidgets('deltas that arrive while a reset waits for the end of the '
      'frame are left to it', (tester) async {
    final c = _Peer(PeerId.parse('00000000-0000-4000-8000-0000000000d3'));
    addTearDown(c.dispose);
    c.type(0, 'hello');

    await tester.pumpWidget(
      Builder(
        builder: (context) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            c.handler.insert(c.handler.length, ' world');
          });
          c.handler.insert(0, 'oh, ');
          return const SizedBox();
        },
      ),
    );

    expect(tester.takeException(), isNull);
    expect(c.plain, 'oh, hello world\n');
  });

  group('with a CRDTUndoManager', () {
    late _Peer ua;
    late _Peer ub;

    setUp(() async {
      ua = _Peer(
        PeerId.parse('00000000-0000-4000-8000-0000000000c1'),
        undo: true,
      );
      ub = _Peer(
        PeerId.parse('00000000-0000-4000-8000-0000000000c2'),
        undo: true,
      );
      await _pump();
    });

    tearDown(() {
      ua.dispose();
      ub.dispose();
    });

    test('undo and redo take back the text and the format', () {
      ua.type(0, 'hello');
      ua.manager!.stopCapturing();
      ua.format(0, 5, Attribute.bold);
      _sync(ua, ub);

      ua.controller.undo();
      _sync(ua, ub);
      expect(ua.content, Delta()..insert('hello\n'));
      // The caret goes after the last insert or retain, as in Quill.
      expect(ua.controller.selection, const TextSelection.collapsed(offset: 5));
      _expectConverged(ua, ub);

      ua.controller.undo();
      _sync(ua, ub);
      expect(ua.handler.text, '');
      _expectConverged(ua, ub);

      expect(ua.controller.selection, const TextSelection.collapsed(offset: 0));
      ua.controller
        ..redo()
        ..redo();
      _sync(ua, ub);
      expect(ua.controller.selection, const TextSelection.collapsed(offset: 5));
      expect(
        ua.content,
        Delta()
          ..insert('hello', {'bold': true})
          ..insert('\n'),
      );
      _expectConverged(ua, ub);
    });

    test('a peer edit is not undone, and it survives the undo', () {
      ua.type(0, 'hello world');
      _sync(ua, ub);
      ua.manager!.stopCapturing();
      ua.format(0, 5, Attribute.bold);
      ub.type(2, 'XX');
      _sync(ua, ub);

      ua.controller.undo();
      _sync(ua, ub);

      expect(ua.handler.text, 'heXXllo world');
      expect(ua.handler.attributesAt(2), isEmpty);
      _expectConverged(ua, ub);
      expect(ub.controller.hasUndo, isTrue);
    });

    test('undo brings a deleted embed back with its data', () {
      ua.type(0, 'ab');
      ua.controller.replaceText(1, 0, BlockEmbed.image('a.png'), null);
      ua.manager!.stopCapturing();
      ua.delete(1, 1);
      _sync(ua, ub);
      expect(ub.plain, 'ab\n');

      ua.controller.undo();
      _sync(ua, ub);
      expect(ua.content.toList()[1].data, {'image': 'a.png'});
      _expectConverged(ua, ub);

      ua.controller.redo();
      _sync(ua, ub);
      expect(ua.plain, 'ab\n');
      _expectConverged(ua, ub);
    });

    test('an image is inserted, restored from a snapshot, updated, deleted '
        'and undone through Quill, on every peer', () async {
      const first = 'https://example.com/a.png';
      const second = 'https://example.com/b.png';
      final uc = _Peer(PeerId.parse('00000000-0000-4000-8000-0000000000c3'));
      addTearDown(uc.dispose);
      await _pump();

      void syncAll() {
        _sync(ua, ub);
        _sync(ua, uc);
        _sync(ub, uc);
      }

      List<Object?> handlerEmbeds(_Peer p) => [
        for (final span in p.handler.value)
          if (span.embed != null) span.embed,
      ];
      List<Object?> quillEmbeds(_Peer p) => [
        for (final op in p.content.toList())
          if (op.data is Map) op.data,
      ];
      void expectImage(List<(String, _Peer)> peers, String? url, String step) {
        final expected = url == null
            ? <Object?>[]
            : [
                {'type': 'image', 'src': url},
              ];
        final document = quillDocumentFromSpans(peers.first.$2.handler.value);
        for (final (name, peer) in peers) {
          expect(handlerEmbeds(peer), expected, reason: '$step: $name handler');
          expect(quillEmbeds(peer), [
            if (url != null) {'image': url},
          ], reason: '$step: $name Quill');
          expect(peer.content, document, reason: '$step: $name Quill');
          expect(
            peer.handler.value,
            peers.first.$2.handler.value,
            reason: '$step: $name handler',
          );
        }
      }

      final all = [('A', ua), ('B', ub), ('C', uc)];

      // 1. A inserts the image through its Quill, B shows it.
      ua.type(0, 'ab');
      ua.controller.replaceText(ua.at(1), 0, BlockEmbed.image(first), null);
      ua.manager!.stopCapturing();
      _sync(ua, ub);
      expectImage([('A', ua), ('B', ub)], first, 'insert');

      // 2. C starts from a snapshot of A, its history pruned.
      final snapshot = ua.document.takeSnapshot();
      expect(ua.document.exportChanges(), isEmpty);
      expect(uc.document.importSnapshot(snapshot), isTrue);
      expectImage(all, first, 'snapshot');

      // 3. B updates the image through its Quill: one embed update, the
      // same element on every peer.
      final deltas = {for (final (name, _) in all) name: <RichTextDelta>[]};
      for (final (name, peer) in all) {
        final watcher = peer.handler.watch().listen((update) {
          if (update case HandlerDelta(:final delta)) deltas[name]!.add(delta);
        });
        addTearDown(watcher.cancel);
      }
      await _pump();
      final embedAt = ub.handler.text.indexOf(RichTextSpan.objectReplacement);
      final changes = ub.document.exportChanges().length;
      ub.controller.replaceText(
        ub.at(embedAt),
        1,
        Delta()..insert({'image': second}),
        null,
      );
      expect(ub.document.exportChanges(), hasLength(changes + 1));
      syncAll();
      for (final (name, _) in all) {
        expect(deltas[name], [
          RichTextDelta([
            RichTextRetain(embedAt),
            RichTextUpdateEmbed({'type': 'image', 'src': second}),
          ]),
        ], reason: 'update: $name handler');
      }
      expectImage(all, second, 'update');

      // 4. A deletes the image through its Quill, and the manager brings it
      // back with the data of B's update.
      ua.delete(embedAt, 1);
      syncAll();
      expectImage(all, null, 'delete');

      ua.manager!.undo();
      syncAll();
      expectImage(all, second, 'undo');
    });

    test('hasUndo and hasRedo follow the manager', () async {
      ub.type(0, 'remote');
      _sync(ua, ub);
      expect(ua.controller.hasUndo, isFalse);

      ua.type(6, '!');
      await _pump();
      expect(ua.controller.hasUndo, isTrue);
      expect(ua.controller.hasRedo, isFalse);
      // One stack only: Quill's own history records nothing.
      expect(ua.controller.document.history.hasUndo, isFalse);

      ua.controller.undo();
      expect(ua.controller.hasUndo, isFalse);
      expect(ua.controller.hasRedo, isTrue);
    });

    test('a manager set later takes over from the Quill history', () async {
      a.manager = CRDTUndoManager(a.document, trackedOrigins: {crdtQuillOrigin})
        ..track(a.handler);
      a.quill.undoManager = a.manager;

      a.type(0, 'hi');
      await _pump();

      expect(a.controller.document.history.hasUndo, isFalse);
      expect(a.controller.hasUndo, isTrue);
    });

    test('a Quill step from before a manager set later is not undone', () {
      a.type(0, 'ab');
      a.quill.undoManager = a.manager = CRDTUndoManager(
        a.document,
        trackedOrigins: {crdtQuillOrigin},
      )..track(a.handler);
      a.type(2, 'cd');

      a.controller.undo();
      expect(a.handler.text, 'ab');
      a.controller.undo();
      expect(a.handler.text, 'ab');
    });

    test('an undo that changes nothing leaves the caret', () {
      ua.type(0, 'abcdef');
      ua.manager!.stopCapturing();
      ua.type(0, 'ZZ');
      _sync(ua, ub);
      ub.delete(0, 2);
      _sync(ua, ub);
      select(ua, 4);

      ua.controller.undo();

      expect(ua.handler.text, 'abcdef');
      expect(ua.controller.selection, const TextSelection.collapsed(offset: 4));
    });

    test('once disposed, the controller records its undo again', () {
      ua.quill.dispose();
      ua.type(0, 'x');

      expect(ua.controller.document.history.hasUndo, isTrue);
    });

    test('only the writes of the editor are recorded', () {
      ua.handler.insert(0, 'direct');
      expect(ua.controller.hasUndo, isFalse);

      ua.type(6, '!');
      expect(ua.controller.hasUndo, isTrue);
    });
  });
}
