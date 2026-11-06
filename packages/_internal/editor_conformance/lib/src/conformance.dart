// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:editor_conformance/src/harness.dart';
import 'package:editor_conformance/src/text_boundaries.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _id = 'doc';

/// Registers the tests every editor binding must pass.
///
/// [create] returns a new harness for each test. The suite checks what any
/// binding owes its users: local edits reach the handler, remote changes
/// reach the editor with the selection kept, an IME composition survives a
/// remote change, and the editor follows the handler to its deletion. Tests
/// of one binding (spans, the last newline of Quill) stay in its own package.
void runEditorConformanceTests(
  String name,
  EditorHarness Function() create,
) {
  group('$name conforms to the editor suite', () {
    late EditorHarness editor;
    late CRDTDocument document;
    late ConformanceHandler handler;

    setUp(() {
      editor = create();
      document = CRDTDocument(peerId: PeerId.generate());
      handler = editor.createHandler(document, _id);
    });

    Future<void> mount(
      WidgetTester tester, {
      VoidCallback? onBuild,
      WidgetBuilder? deletedBuilder,
    }) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: editor.build(
                document,
                _id,
                onBuild: onBuild,
                deletedBuilder: deletedBuilder,
              ),
            ),
          ),
        );

    // A peer that shares the history of [document], so the positions of its
    // edits are known.
    ({CRDTDocument document, ConformanceHandler handler}) remotePeer() {
      final remote = CRDTDocument(peerId: PeerId.generate());
      final remoteHandler = editor.createHandler(remote, _id);
      remote.importChanges(document.exportChanges());
      return (document: remote, handler: remoteHandler);
    }

    void receive(CRDTDocument remote) {
      document.importChanges(
        remote.exportChanges(fromVersionVector: document.getVersionVector()),
      );
    }

    testWidgets('local edits reach the handler', (tester) async {
      await mount(tester);

      editor.replaceText(0, 0, 'hello');
      await tester.pump();
      expect(handler.text, 'hello');

      editor.replaceText(2, 2, 'XY');
      await tester.pump();
      expect(handler.text, 'heXYllo');

      editor.replaceText(1, 5, '');
      await tester.pump();
      expect(handler.text, 'hlo');
      expect(editor.editorText, 'hlo');
    });

    testWidgets('an emoji is one position of the handler', (tester) async {
      await mount(tester);

      editor.replaceText(0, 0, 'a😀b');
      await tester.pump();
      expect(handler.length, 3);
      expect(editor.editorText.length, 4);

      // A backspace after the emoji deletes both of its code units.
      editor.replaceText(1, 3, '');
      await tester.pump();
      expect(handler.text, 'ab');
      expect(editor.editorText, 'ab');
    });

    testWidgets('a remote insert shows without a rebuild, caret kept', (
      tester,
    ) async {
      var builds = 0;
      handler.insert(0, 'hello world');
      await mount(tester, onBuild: () => builds++);
      editor.selection = const TextSelection.collapsed(offset: 5);

      final peer = remotePeer();
      peer.handler.insert(0, 'XXX ');
      receive(peer.document);
      await tester.pump();

      expect(editor.editorText, 'XXX hello world');
      expect(editor.selection, const TextSelection.collapsed(offset: 9));
      expect(builds, 1);
    });

    testWidgets('the caret moves by code units past an emoji', (tester) async {
      handler.insert(0, 'a😀b');
      await mount(tester);
      editor.selection = const TextSelection.collapsed(offset: 3);

      final peer = remotePeer();
      peer.handler.insert(0, '🎉');
      receive(peer.document);
      await tester.pump();

      expect(editor.editorText, '🎉a😀b');
      expect(editor.selection, const TextSelection.collapsed(offset: 5));
    });

    testWidgets('a change at both ends does not drag the caret', (
      tester,
    ) async {
      handler.insert(0, 'hello world');
      await mount(tester);
      editor.selection = const TextSelection.collapsed(offset: 5);

      final peer = remotePeer();
      peer.handler
        ..insert(0, 'A')
        ..insert(12, 'B');
      receive(peer.document);
      await tester.pump();

      expect(editor.editorText, 'Ahello worldB');
      expect(editor.selection, const TextSelection.collapsed(offset: 6));
    });

    testWidgets('a batch of remote changes keeps the caret at the end', (
      tester,
    ) async {
      handler.insert(0, 'abc');
      await mount(tester);
      editor.selection = const TextSelection.collapsed(offset: 3);

      final peer = remotePeer();
      peer.handler
        ..insert(0, 'X')
        ..insert(0, 'Y')
        ..insert(0, 'Z');
      receive(peer.document);
      await tester.pump();

      expect(editor.editorText, 'ZYXabc');
      expect(editor.selection, const TextSelection.collapsed(offset: 6));
    });

    testWidgets('a remote replacement keeps the caret at the end', (
      tester,
    ) async {
      handler.insert(0, 'hello world');
      await mount(tester);
      editor.selection = const TextSelection.collapsed(offset: 11);

      final peer = remotePeer();
      peer.document.runInTransaction(() {
        peer.handler
          ..delete(0, 5)
          ..insert(0, 'HEY');
      });
      receive(peer.document);
      await tester.pump();

      expect(editor.editorText, 'HEY world');
      expect(editor.selection, const TextSelection.collapsed(offset: 9));
    });

    testWidgets('a remote deletion shows', (tester) async {
      handler.insert(0, 'hello world');
      await mount(tester);

      final peer = remotePeer();
      peer.handler.delete(0, 6);
      receive(peer.document);
      await tester.pump();

      expect(editor.editorText, 'world');
    });

    testWidgets('two editors follow each other', (tester) async {
      final other = create();
      final otherDocument = CRDTDocument(peerId: PeerId.generate());
      final otherHandler = other.createHandler(otherDocument, _id);
      final links = [
        document.localChanges.listen(otherDocument.applyChange),
        otherDocument.localChanges.listen(document.applyChange),
      ];
      addTearDown(() async {
        for (final link in links) {
          await link.cancel();
        }
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                Expanded(child: editor.build(document, _id)),
                Expanded(child: other.build(otherDocument, _id)),
              ],
            ),
          ),
        ),
      );

      editor.replaceText(0, 0, 'hello');
      await tester.pump();
      expect(other.editorText, 'hello');

      other.replaceText(5, 5, ' world');
      await tester.pump();
      expect(editor.editorText, 'hello world');
      expect(handler.text, otherHandler.text);
    });

    testWidgets('a deleted handler shows the deleted builder', (tester) async {
      handler.insert(0, 'hello');
      await mount(tester, deletedBuilder: (_) => const Text('gone'));

      document.deleteHandler(handler.raw);
      await tester.pump();
      await tester.pump();

      expect(find.text('gone'), findsOneWidget);
    });

    testWidgets('another handler type is refused', (tester) async {
      final wrong = CRDTDocument(peerId: PeerId.generate());
      CRDTListHandler<String>(
        wrong,
        _id,
        handlerType: 'CRDTListHandler<String>',
      );

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: editor.build(wrong, _id))),
      );

      expect(tester.takeException(), isA<FlutterError>());
    });

    testWidgets('a random stream of edits keeps editor and handler equal', (
      tester,
    ) async {
      for (final seed in [7, 13, 29, 101, 997]) {
        await _randomStream(
          tester,
          seed: seed,
          harness: create(),
          composes: editor.supportsComposition,
        );
      }
    });

    if (create().supportsComposition) {
      testWidgets('nothing is committed while a composition is active', (
        tester,
      ) async {
        await mount(tester);

        await editor.ime(
          tester,
          const TextEditingValue(
            text: 'nihao',
            selection: TextSelection.collapsed(offset: 5),
            composing: TextRange(start: 0, end: 5),
          ),
        );
        expect(handler.text, '');

        await editor.ime(
          tester,
          const TextEditingValue(
            text: '你好',
            selection: TextSelection.collapsed(offset: 2),
          ),
        );
        expect(handler.text, '你好');
      });

      testWidgets('a remote change keeps the pending composition', (
        tester,
      ) async {
        handler.insert(0, 'hello');
        await mount(tester);
        final peer = remotePeer();

        await editor.ime(
          tester,
          const TextEditingValue(
            text: 'helloX',
            selection: TextSelection.collapsed(offset: 6),
            composing: TextRange(start: 5, end: 6),
          ),
        );
        expect(handler.text, 'hello');

        peer.handler.insert(0, 'A ');
        receive(peer.document);
        await tester.pumpAndSettle();

        expect(handler.text, 'A helloX');
        expect(editor.editorText, handler.text);
      });
    }

    if (create().supportsEmbeds) {
      testWidgets('edits around an embed keep it', (tester) async {
        handler
          ..insert(0, 'ab')
          ..insertEmbed(1, {'image': 'a.png'});
        await mount(tester);
        expect(editor.editorText, 'a\uFFFCb');

        editor.replaceText(1, 1, 'X');
        await tester.pump();
        editor.replaceText(3, 3, 'Y');
        await tester.pump();
        expect(handler.text, 'aX\uFFFCYb');

        editor.replaceText(1, 2, '');
        await tester.pump();
        expect(handler.text, 'a\uFFFCYb');
        expect(editor.editorText, handler.text);

        editor.replaceText(1, 2, '');
        await tester.pump();
        expect(handler.text, 'aYb');
        expect(editor.editorText, handler.text);
      });

      testWidgets('remote embed changes show, caret kept', (tester) async {
        handler.insert(0, 'hello world');
        await mount(tester);
        editor.selection = const TextSelection.collapsed(offset: 5);
        final peer = remotePeer();

        peer.handler.insertEmbed(0, {'image': 'a.png'});
        receive(peer.document);
        await tester.pump();
        expect(editor.editorText, '\uFFFChello world');
        expect(editor.selection, const TextSelection.collapsed(offset: 6));

        peer.handler.updateEmbed(0, {'image': 'b.png'});
        receive(peer.document);
        await tester.pump();
        expect(editor.editorText, '\uFFFChello world');
        expect(editor.selection, const TextSelection.collapsed(offset: 6));

        peer.handler.delete(0, 1);
        receive(peer.document);
        await tester.pump();
        expect(editor.editorText, 'hello world');
        expect(editor.selection, const TextSelection.collapsed(offset: 5));
      });

      testWidgets('a typed U+FFFC is not written, the rest is', (
        tester,
      ) async {
        handler.insert(0, 'ab');
        await mount(tester);

        editor.replaceText(1, 1, 'x\uFFFCy');
        await tester.pump();

        expect(handler.text, 'axyb');
        expect(editor.editorText, 'axyb');
        expect(editor.selection, const TextSelection.collapsed(offset: 3));

        editor.replaceText(0, 0, '\uFFFC');
        await tester.pump();
        expect(handler.text, 'axyb');
        expect(editor.editorText, 'axyb');
      });
    }
  });
}

// Edits, compositions and remote changes in a random order. The editor and
// the handler must hold the same text after every round.
Future<void> _randomStream(
  WidgetTester tester, {
  required int seed,
  required EditorHarness harness,
  required bool composes,
}) async {
  final document = CRDTDocument(peerId: PeerId.generate());
  final handler = harness.createHandler(document, _id)
    ..insert(0, 'hello world');
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: harness.build(document, _id))),
  );
  final remote = CRDTDocument(peerId: PeerId.generate());
  final remoteHandler = harness.createHandler(remote, _id);
  remote.importChanges(document.exportChanges());
  final random = Random(seed);
  var composing = false;

  for (var round = 0; round < 150; round++) {
    final text = harness.editorText;
    switch (random.nextInt(composes ? 7 : 5)) {
      case 0 || 1:
        if (composing) {
          break;
        }
        final at = runeBoundary(text, random.nextInt(text.length + 1));
        harness.replaceText(
          at,
          at,
          random.nextInt(6) == 0
              ? '😀'
              : String.fromCharCode(97 + random.nextInt(26)),
        );
      case 2:
        if (composing || text.isEmpty) {
          break;
        }
        final at = runeBoundary(text, random.nextInt(text.length));
        harness.replaceText(at, nextRune(text, at), '');
      case 3 || 4:
        remote.importChanges(
          document.exportChanges(fromVersionVector: remote.getVersionVector()),
        );
        for (var i = 0; i < 1 + random.nextInt(3); i++) {
          final length = remoteHandler.length;
          if (random.nextBool() || length == 0) {
            remoteHandler.insert(
              random.nextInt(length + 1),
              random.nextInt(6) == 0
                  ? '🎉'
                  : String.fromCharCode(65 + random.nextInt(26)),
            );
          } else {
            remoteHandler.delete(random.nextInt(length), 1);
          }
        }
        document.importChanges(
          remote.exportChanges(fromVersionVector: document.getVersionVector()),
        );
      case 5:
        if (composing) {
          break;
        }
        composing = true;
        await harness.ime(
          tester,
          TextEditingValue(
            text: '${text}zz',
            selection: TextSelection.collapsed(offset: text.length + 2),
            composing: TextRange(start: text.length, end: text.length + 2),
          ),
        );
      default:
        if (!composing) {
          break;
        }
        await harness.ime(
          tester,
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          ),
        );
    }

    await tester.pumpAndSettle();
    // A remote change commits a composition, an empty import does not.
    composing = harness.editorText != handler.text && composing;
    if (!composing) {
      expect(
        harness.editorText,
        handler.text,
        reason: 'seed $seed round $round',
      );
    }
  }
}
