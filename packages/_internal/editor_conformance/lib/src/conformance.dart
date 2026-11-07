// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:editor_conformance/src/harness.dart';
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
      SelectionAnchorsListener? onSelectionAnchorsChanged,
      CRDTUndoManager? undoManager,
    }) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: editor.build(
                document,
                _id,
                onBuild: onBuild,
                deletedBuilder: deletedBuilder,
                onSelectionAnchorsChanged: onSelectionAnchorsChanged,
                undoManager: undoManager,
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

    if (create().supportsAnchors) {
      group('selection anchors', () {
        final published = <(FugueElementID?, FugueElementID?)>[];

        setUp(published.clear);

        Future<void> mountFocused(WidgetTester tester) async {
          await mount(
            tester,
            onSelectionAnchorsChanged: (base, extent) =>
                published.add((base, extent)),
          );
          await editor.focus(tester);
        }

        testWidgets('a selection publishes its anchors, in runes', (
          tester,
        ) async {
          handler.insert(0, 'a😀bc');
          await mountFocused(tester);

          editor.selection = const TextSelection(
            baseOffset: 1,
            extentOffset: 4,
          );
          await tester.pump();

          expect(
            published.last,
            (
              handler.stablePositionAt(1),
              handler.stablePositionAt(3),
            ),
          );
        });

        testWidgets('a local edit moves the anchors', (tester) async {
          await mountFocused(tester);

          editor.replaceText(0, 0, 'a😀b');
          await tester.pump();

          expect(published.last.$2, handler.stablePositionAt(3));
        });

        testWidgets('nothing is published without the focus', (tester) async {
          handler.insert(0, 'hello');
          await mount(
            tester,
            onSelectionAnchorsChanged: (base, extent) =>
                published.add((base, extent)),
          );

          editor.selection = const TextSelection.collapsed(offset: 2);
          await tester.pump();

          expect(published, isEmpty);
        });

        testWidgets('a blur withdraws the anchors, once', (tester) async {
          handler.insert(0, 'hello');
          await mountFocused(tester);
          editor.selection = const TextSelection.collapsed(offset: 2);
          await tester.pump();
          expect(published.last.$2, isNotNull);

          tester.binding.focusManager.primaryFocus?.unfocus();
          await tester.pump();
          final withdrawn = published.length;
          editor.selection = const TextSelection.collapsed(offset: 3);
          await tester.pump();

          expect(published.last, (null, null));
          expect(published, hasLength(withdrawn));
        });

        testWidgets('an anchor survives a remote insert before it', (
          tester,
        ) async {
          handler.insert(0, 'hello');
          await mountFocused(tester);
          editor.selection = const TextSelection.collapsed(offset: 5);
          await tester.pump();
          final extent = published.last.$2!;

          final peer = remotePeer();
          peer.handler.insert(0, 'XXX ');
          receive(peer.document);
          await tester.pump();

          expect(published.last.$2, extent);
          expect(handler.indexOfStablePosition(extent), 9);
        });

        testWidgets('a batch of remote changes publishes no stale anchor', (
          tester,
        ) async {
          handler.insert(0, 'abc');
          await mountFocused(tester);
          editor.selection = const TextSelection.collapsed(offset: 3);
          await tester.pump();
          final before = published.length;

          final peer = remotePeer();
          peer.handler
            ..insert(0, 'X')
            ..insert(0, 'Y')
            ..insert(0, 'Z');
          receive(peer.document);
          await tester.pump();

          // The caret stays after the same element all along.
          expect(published, hasLength(before));
        });
      });
    }

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

    group('a write another watcher makes inside a push', () {
      // Same length as the edit: only the echo check can see it.
      final writes = <String, void Function()>{
        'text': () => handler
          ..delete(0, 1)
          ..insert(0, 'H'),
        if (create().supportsFormat)
          'format': () => handler.format(0, 2, 'bold', true),
        if (create().supportsEmbeds)
          'embed update': () => handler.updateEmbed(5, {'image': 'b.png'}),
      };
      for (final MapEntry(key: kind, value: write) in writes.entries) {
        testWidgets('is taken in: $kind', (tester) async {
          handler.insert(0, 'hello');
          if (kind == 'embed update') {
            handler.insertEmbed(5, {'image': 'a.png'});
          }
          var armed = true;
          final watcher = handler.watch().listen((_) {
            if (armed && handler.text.endsWith('X')) {
              armed = false;
              write();
            }
          });
          addTearDown(watcher.cancel);
          await mount(tester);

          final end = editor.editorText.length;
          editor.replaceText(end, end, 'X');
          await tester.pumpAndSettle();

          expect(armed, isFalse);
          expect(editor.editorText, handler.text);
          if (kind == 'embed update') {
            expect(handler.embedAt(5), {'image': 'b.png'});
          }
          final peer = remotePeer();
          peer.handler.insert(0, '>');
          receive(peer.document);
          await tester.pump();
          expect(editor.editorText, handler.text);
        });
      }
    });

    if (create().supportsComposition) {
      group('a composition commits over a remote change in its range', () {
        // Pinned: what the peer wrote has to survive the commit on both
        // sides.
        final local = PeerId.parse('00000000-0000-4000-8000-00000000000a');
        final peerId = PeerId.parse('00000000-0000-4000-8000-00000000000b');

        Future<void> commitOver(
          WidgetTester tester, {
          required void Function(ConformanceHandler handler) write,
          required String expected,
        }) async {
          document = CRDTDocument(peerId: local);
          handler = editor.createHandler(document, _id)..insert(0, 'teh');
          await mount(tester);
          await editor.ime(
            tester,
            const TextEditingValue(
              text: 'the',
              selection: TextSelection.collapsed(offset: 3),
              composing: TextRange(start: 0, end: 3),
            ),
          );

          final remote = CRDTDocument(peerId: peerId);
          final remoteHandler = editor.createHandler(remote, _id);
          remote.importChanges(document.exportChanges());
          write(remoteHandler);
          receive(remote);
          await tester.pump();

          remote.importChanges(
            document.exportChanges(
              fromVersionVector: remote.getVersionVector(),
            ),
          );
          expect(handler.text, expected);
          expect(remoteHandler.text, expected);
          expect(editor.editorText, expected);
        }

        testWidgets('an insert at its start', (tester) async {
          await commitOver(
            tester,
            write: (peer) => peer.insert(1, 'REMOTE'),
            expected: 'tREMOTEhe',
          );
        });

        testWidgets('an insert inside it', (tester) async {
          await commitOver(
            tester,
            write: (peer) => peer.insert(2, 'REMOTE'),
            expected: 'theREMOTE',
          );
        });

        if (create().supportsEmbeds) {
          testWidgets('an embed at its start', (tester) async {
            await commitOver(
              tester,
              write: (peer) => peer.insertEmbed(1, {'image': 'a.png'}),
              expected: 't￼he',
            );
            expect(handler.embedAt(1), {'image': 'a.png'});
          });

          testWidgets('an embed inside it', (tester) async {
            await commitOver(
              tester,
              write: (peer) => peer.insertEmbed(2, {'image': 'a.png'}),
              expected: 'the￼',
            );
            expect(handler.embedAt(3), {'image': 'a.png'});
          });
        }
      });

      if (create().supportsAnchors) {
        testWidgets('anchors are withdrawn while a composition is pending', (
          tester,
        ) async {
          final published = <FugueElementID?>[];
          handler.insert(0, 'hello');
          await mount(
            tester,
            onSelectionAnchorsChanged: (base, extent) => published.add(base),
          );
          await editor.focus(tester);
          editor.selection = const TextSelection.collapsed(offset: 5);
          await tester.pump();
          expect(published.last, isNotNull);

          await editor.ime(
            tester,
            const TextEditingValue(
              text: 'helloあ',
              selection: TextSelection.collapsed(offset: 6),
              composing: TextRange(start: 5, end: 6),
            ),
          );
          expect(published.last, isNull);
        });
      }
    }

    if (create().supportsUndo) {
      group('with a CRDTUndoManager', () {
        late CRDTUndoManager manager;

        setUp(() {
          manager = CRDTUndoManager(document, trackedOrigins: {editor.origin})
            ..track(handler.raw);
        });

        tearDown(() => manager.dispose());

        testWidgets('undo and redo take back a local edit, caret after it', (
          tester,
        ) async {
          await mount(tester, undoManager: manager);
          editor.replaceText(0, 0, 'hello');
          await tester.pump();

          editor.undo();
          await tester.pump();
          expect(handler.text, '');
          expect(editor.editorText, '');

          editor.redo();
          await tester.pump();
          expect(handler.text, 'hello');
          expect(editor.editorText, 'hello');
          expect(editor.selection, const TextSelection.collapsed(offset: 5));
        });

        testWidgets('only the writes of the editor are recorded', (
          tester,
        ) async {
          await mount(tester, undoManager: manager);

          handler.insert(0, 'direct');
          await tester.pump();
          expect(manager.canUndo, isFalse);

          editor.replaceText(6, 6, '!');
          await tester.pump();
          expect(manager.canUndo, isTrue);
        });

        testWidgets('a peer edit is not undone, and it survives the undo', (
          tester,
        ) async {
          handler.insert(0, 'world');
          await mount(tester, undoManager: manager);
          editor.replaceText(0, 0, 'hello ');
          await tester.pump();

          final peer = remotePeer();
          peer.handler.insert(11, '!');
          receive(peer.document);
          await tester.pump();

          editor.undo();
          await tester.pump();
          expect(handler.text, 'world!');
          expect(editor.editorText, 'world!');
        });

        testWidgets('an undo that changes nothing leaves the caret', (
          tester,
        ) async {
          handler.insert(0, 'abcdef');
          await mount(tester, undoManager: manager);
          editor.replaceText(0, 0, 'ZZ');
          await tester.pump();

          final peer = remotePeer();
          peer.handler.delete(0, 2);
          receive(peer.document);
          await tester.pump();
          editor
            ..selection = const TextSelection.collapsed(offset: 4)
            ..undo();
          await tester.pump();
          expect(handler.text, 'abcdef');
          expect(editor.selection, const TextSelection.collapsed(offset: 4));
        });

        if (create().supportsEmbeds) {
          testWidgets('undo brings a deleted embed back with its data', (
            tester,
          ) async {
            handler
              ..insert(0, 'ab')
              ..insertEmbed(1, {'image': 'a.png'});
            await mount(tester, undoManager: manager);
            editor.replaceText(1, 2, '');
            await tester.pump();
            expect(handler.text, 'ab');

            editor.undo();
            await tester.pump();
            expect(editor.editorText, 'a￼b');
            expect(handler.embedAt(1), {'image': 'a.png'});

            editor.redo();
            await tester.pump();
            expect(editor.editorText, 'ab');
          });
        }

        if (create().supportsFormat) {
          testWidgets('a format is a step of its own, apart from the typing', (
            tester,
          ) async {
            await mount(tester, undoManager: manager);
            editor
              ..replaceText(0, 0, 'abc')
              ..format(0, 3, 'bold', true)
              ..replaceText(3, 3, 'd');
            await tester.pump();

            editor.undo();
            await tester.pump();
            expect(handler.text, 'abc');
            expect(handler.attributesAt(0), {'bold': true});

            editor.undo();
            await tester.pump();
            expect(handler.text, 'abc');
            expect(handler.attributesAt(0), isEmpty);

            editor.undo();
            await tester.pump();
            expect(handler.text, '');
          });
        }
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
        final at = RuneOffsets.snap(text, random.nextInt(text.length + 1));
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
        final at = RuneOffsets.snap(text, random.nextInt(text.length));
        harness.replaceText(at, RuneOffsets.skip(text, at, 1), '');
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
