// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:math';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart' hide ChangeSource;
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_lf_quill/crdt_lf_quill.dart';
import 'package:crdt_lf_quill/src/crdt_quill_binding.dart';
import 'package:flutter/widgets.dart'
    show Builder, Column, ListenableBuilder, SizedBox, TextSelection;
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
    quill = CrdtQuillBinding(controller, undoManager: manager);
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
    a.handler.insertEmbed(0, {'image': 'a.png'});
    final writes = <void Function()>[
      () => a.handler.format(1, 2, 'bold', true),
      () => a.handler.update(2, 'E'),
      () => a.handler.updateEmbed(0, {'image': 'b.png'}),
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
          RichTextUpdateEmbed({'image': 'b.png'}),
        ]),
      ]);
      _sync(a, b);
      expect(b.content.toList()[1].data, {'image': 'b.png'});

      deltas.clear();
      a.controller.replaceText(1, 1, BlockEmbed.image('c.png'), null);
      expect(deltas, [
        RichTextDelta([
          RichTextRetain(2),
          RichTextInsertEmbed({'image': 'c.png'}),
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
      RichTextSpan.embed({'image': 'a.png'}, {'bold': true}),
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
      _expectConverged(ua, ub);

      ua.controller.undo();
      _sync(ua, ub);
      expect(ua.handler.text, '');
      _expectConverged(ua, ub);

      ua.controller
        ..redo()
        ..redo();
      _sync(ua, ub);
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
                {'image': url},
              ];
        final document = quillDocumentFromSpans(peers.first.$2.handler.value);
        for (final (name, peer) in peers) {
          expect(handlerEmbeds(peer), expected, reason: '$step: $name handler');
          expect(quillEmbeds(peer), expected, reason: '$step: $name Quill');
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
            RichTextUpdateEmbed({'image': second}),
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

    test('only the writes of the editor are recorded', () {
      ua.handler.insert(0, 'direct');
      expect(ua.controller.hasUndo, isFalse);

      ua.type(6, '!');
      expect(ua.controller.hasUndo, isTrue);
    });
  });
}
