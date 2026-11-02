// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:editor_conformance/editor_conformance.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/controller_harness.dart';

void main() {
  runEditorConformanceTests(
    'CrdtRichTextFieldBuilder',
    () => ControllerHarness(
      makeHandler: CRDTFugueRichTextHandler.new,
      buildField: (id, deletedBuilder, onController) =>
          CrdtRichTextFieldBuilder(
        id: id,
        deletedBuilder: deletedBuilder,
        builder: (context, controller) {
          onController(controller);
          return TextField(controller: controller, maxLines: null);
        },
      ),
    ),
  );

  late CRDTDocument doc;
  late CrdtRichTextEditingController? controller;
  var builds = 0;
  final anchors = <(FugueElementID?, FugueElementID?)>[];

  setUp(() {
    doc = CRDTDocument(peerId: PeerId.generate());
    controller = null;
    builds = 0;
    anchors.clear();
  });

  Widget host({
    CRDTUndoManager? undoManager,
  }) {
    return CrdtProvider.value(
      value: doc,
      child: MaterialApp(
        home: Scaffold(
          body: CrdtRichTextFieldBuilder(
            id: 'page',
            undoManager: undoManager,
            onSelectionAnchorsChanged: (base, extent) =>
                anchors.add((base, extent)),
            builder: (context, c) {
              builds++;
              controller = c;
              return TextField(
                controller: c,
                maxLines: null,
                strutStyle: StrutStyle.disabled,
              );
            },
          ),
        ),
      ),
    );
  }

  CRDTFugueRichTextHandler pageOf(CRDTDocument d) =>
      d.registeredHandlers['page']! as CRDTFugueRichTextHandler;

  CRDTDocument remotePeer() {
    final remote = CRDTDocument(peerId: PeerId.generate());
    CRDTFugueRichTextHandler(remote, 'page');
    remote.importChanges(doc.exportChanges());
    return remote;
  }

  void syncFrom(CRDTDocument remote) {
    doc.importChanges(
      remote.exportChanges(fromVersionVector: doc.getVersionVector()),
    );
  }

  /// The painted style of the code unit at [offset].
  TextStyle? paintedStyleAt(WidgetTester tester, int offset) {
    final editable = tester.allRenderObjects.whereType<RenderEditable>().first;
    TextStyle? found;
    var at = 0;
    (editable.text! as TextSpan).visitChildren((span) {
      final text = (span as TextSpan).text ?? '';
      if (offset >= at && offset < at + text.length) {
        found = span.style;
        return false;
      }
      at += text.length;
      return true;
    });
    return found;
  }

  void expectInSync(String reason) {
    final handler = pageOf(doc);
    expect(controller!.text, handler.text, reason: reason);
    expect(
      sameRuneAttributes(controller!.spans, handler.value),
      isTrue,
      reason: '$reason: ${controller!.spans} vs ${handler.value}',
    );
  }

  testWidgets('typing and a format reach the other peer', (tester) async {
    final alice = CRDTDocument(peerId: PeerId.generate());
    final bob = CRDTDocument(peerId: PeerId.generate());
    CRDTFugueRichTextHandler(alice, 'page');
    CRDTFugueRichTextHandler(bob, 'page');
    final links = [
      alice.localChanges.listen(bob.applyChange),
      bob.localChanges.listen(alice.applyChange),
    ];
    addTearDown(() async {
      for (final link in links) {
        await link.cancel();
      }
    });
    CrdtRichTextEditingController? a;
    CrdtRichTextEditingController? b;
    Widget side(
      CRDTDocument d,
      void Function(CrdtRichTextEditingController) c,
    ) =>
        Expanded(
          child: CrdtProvider.value(
            value: d,
            child: CrdtRichTextFieldBuilder(
              id: 'page',
              builder: (context, controller) {
                c(controller);
                return TextField(controller: controller);
              },
            ),
          ),
        );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [side(alice, (c) => a = c), side(bob, (c) => b = c)],
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'hello world');
    await tester.pump();
    expect(b!.text, 'hello world');

    a!.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    a!.toggle('bold');
    await tester.pump();

    expect(b!.spans, [
      RichTextSpan('hello', {'bold': true}),
      RichTextSpan(' world'),
    ]);
    expect(a!.attributeAtSelection('bold'), isTrue);
    expect(
      a!.selection,
      const TextSelection(baseOffset: 0, extentOffset: 5),
    );
  });

  testWidgets('a remote format repaints in place', (tester) async {
    CRDTFugueRichTextHandler(doc, 'page').insert(0, 'hello world');
    await tester.pumpWidget(host());
    controller!.selection = const TextSelection.collapsed(offset: 3);
    await tester.pump();
    expect(paintedStyleAt(tester, 1)?.fontWeight, isNull);

    final remote = remotePeer();
    pageOf(remote).format(0, 5, 'bold', true);
    syncFrom(remote);
    await tester.pump();

    expect(controller!.selection, const TextSelection.collapsed(offset: 3));
    expect(paintedStyleAt(tester, 1)?.fontWeight, FontWeight.bold);
    expect(paintedStyleAt(tester, 7)?.fontWeight, isNull);
    expect(builds, 1);
  });

  testWidgets('a composition is painted with the format before it', (
    tester,
  ) async {
    CRDTFugueRichTextHandler(doc, 'page')
      ..insert(0, 'hello')
      ..format(0, 5, 'bold', true);
    await tester.pumpWidget(host());
    await tester.showKeyboard(find.byType(TextField));

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'helloX',
        selection: TextSelection.collapsed(offset: 6),
        composing: TextRange(start: 5, end: 6),
      ),
    );
    await tester.pump();

    expect(pageOf(doc).text, 'hello');
    expect(paintedStyleAt(tester, 5)!.fontWeight, FontWeight.bold);
    expect(paintedStyleAt(tester, 5)!.decoration, TextDecoration.underline);
    expect(paintedStyleAt(tester, 2)?.decoration, isNull);
  });

  testWidgets('takes in a same-length write served inside a push', (
    tester,
  ) async {
    // Release builds have no assert: the field alone must see the write.
    debugVerifyCrdtRichTextFieldProjection = false;
    addTearDown(() => debugVerifyCrdtRichTextFieldProjection = true);
    final page = CRDTFugueRichTextHandler(doc, 'page')..insert(0, 'hello');
    var armed = true;
    final watcher = page.watch().listen((_) {
      if (armed && page.text == 'helloX') {
        armed = false;
        page
          ..delete(0, 1)
          ..insert(0, 'H');
      }
    });
    addTearDown(watcher.cancel);
    await tester.pumpWidget(host());
    controller!.value = const TextEditingValue(
      text: 'helloX',
      selection: TextSelection.collapsed(offset: 6),
    );
    await tester.pumpAndSettle();

    expect(armed, isFalse);
    expect(page.text, 'HelloX');
    expectInSync('after the watcher');
  });

  testWidgets('anchors are published while the field has focus', (
    tester,
  ) async {
    CRDTFugueRichTextHandler(doc, 'page').insert(0, 'hello');
    await tester.pumpWidget(host());
    expect(anchors, isEmpty);

    await tester.showKeyboard(find.byType(TextField));
    controller!.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();
    expect(anchors.last.$1, pageOf(doc).stablePositionAt(2));

    FocusManager.instance.primaryFocus!.unfocus();
    await tester.pump();
    expect(anchors.last, (null, null));
  });

  testWidgets('pasted text takes the format where it lands, not its own', (
    tester,
  ) async {
    CRDTFugueRichTextHandler(doc, 'page')
      ..insert(0, 'hello world')
      ..format(0, 5, 'bold', true);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? {'text': 'ZZ'} : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(host());
    await tester.showKeyboard(find.byType(TextField));
    final editable = tester.state<EditableTextState>(find.byType(EditableText));

    controller!.selection = const TextSelection.collapsed(offset: 2);
    await editable.pasteText(SelectionChangedCause.keyboard);
    await tester.pump();
    expect(pageOf(doc).value, [
      RichTextSpan('heZZllo', {'bold': true}),
      RichTextSpan(' world'),
    ]);

    // Over a selection that crosses the edge of the format.
    controller!.selection = const TextSelection(baseOffset: 6, extentOffset: 9);
    await editable.pasteText(SelectionChangedCause.keyboard);
    await tester.pump();
    expect(pageOf(doc).text, 'heZZllZZorld');
    expectInSync('paste');
  });

  testWidgets('formats the right runes around emoji', (tester) async {
    CRDTFugueRichTextHandler(doc, 'page').insert(0, 'a😀b😀c');
    await tester.pumpWidget(host());
    // Code units 1..4 are "😀b".
    controller!.selection = const TextSelection(baseOffset: 1, extentOffset: 4);
    controller!.toggle('bold');
    await tester.pump();

    final handler = pageOf(doc);
    expect([
      for (var i = 0; i < 5; i++) handler.attributesAt(i)['bold'],
    ], [
      null,
      true,
      true,
      null,
      null,
    ]);
    expectInSync('emoji');
  });

  testWidgets('the style set at a caret goes to the typed text only', (
    tester,
  ) async {
    CRDTFugueRichTextHandler(doc, 'page').insert(0, 'hello');
    await tester.pumpWidget(host());
    controller!.selection = const TextSelection.collapsed(offset: 5);
    controller!.toggle('bold');
    expect(controller!.attributeAtSelection('bold'), isTrue);
    expect(pageOf(doc).value, [RichTextSpan('hello')]);

    controller!.value = const TextEditingValue(
      text: 'hello\nX',
      selection: TextSelection.collapsed(offset: 7),
    );
    await tester.pump();

    // The newline stays plain: a style there would be a block attribute.
    expect(pageOf(doc).value, [
      RichTextSpan('hello\n'),
      RichTextSpan('X', {'bold': true}),
    ]);

    controller!.selection = const TextSelection.collapsed(offset: 0);
    controller!.toggle('italic');
    controller!.selection = const TextSelection.collapsed(offset: 2);
    expect(controller!.pendingAttributes, isEmpty);
    expectInSync('pending');
  });

  testWidgets('the style ends with the typed text', (tester) async {
    CRDTFugueRichTextHandler(doc, 'page').insert(0, 'hello');
    await tester.pumpWidget(host());
    controller!.selection = const TextSelection.collapsed(offset: 5);
    controller!.toggle('bold');
    controller!.value = const TextEditingValue(
      text: 'helloX',
      selection: TextSelection.collapsed(offset: 6),
    );
    await tester.pump();
    expect(pageOf(doc).attributesAt(5), {'bold': true});

    // The caret comes back to where the style was set: it does not return.
    controller!.value = const TextEditingValue(
      text: 'hello',
      selection: TextSelection.collapsed(offset: 5),
    );
    controller!.value = const TextEditingValue(
      text: 'helloZ',
      selection: TextSelection.collapsed(offset: 6),
    );
    await tester.pump();

    expect(controller!.pendingAttributes, isEmpty);
    expectInSync('pending');
  });

  group('with a CRDTUndoManager', () {
    late CRDTUndoManager manager;

    setUp(() {
      manager = CRDTUndoManager(
        doc,
        trackedOrigins: {crdtRichTextFieldOrigin},
      );
    });

    tearDown(() => manager.dispose());

    testWidgets('undo and redo take back the text and the format', (
      tester,
    ) async {
      manager.track(CRDTFugueRichTextHandler(doc, 'page'));
      await tester.pumpWidget(host(undoManager: manager));
      expect(controller!.canUndo, isFalse);

      controller!.value = const TextEditingValue(
        text: 'hello',
        selection: TextSelection(baseOffset: 0, extentOffset: 5),
      );
      controller!.toggle('bold');
      expect(controller!.canUndo, isTrue);

      controller!.undo();
      await tester.pump();
      expect(pageOf(doc).value, [RichTextSpan('hello')]);
      expectInSync('format undone');
      expect(controller!.canRedo, isTrue);

      controller!.undo();
      await tester.pump();
      expect(controller!.text, '');
      expect(controller!.canUndo, isFalse);

      controller!
        ..redo()
        ..redo();
      await tester.pump();
      expect(pageOf(doc).value, [
        RichTextSpan('hello', {'bold': true}),
      ]);
      expectInSync('redone');
    });

    testWidgets('redo puts the caret after the restored text', (tester) async {
      manager.track(CRDTFugueRichTextHandler(doc, 'page'));
      await tester.pumpWidget(host(undoManager: manager));
      controller!.value = const TextEditingValue(
        text: 'hello',
        selection: TextSelection.collapsed(offset: 5),
      );
      controller!
        ..undo()
        ..selection = const TextSelection.collapsed(offset: 0)
        ..redo();
      await tester.pump();
      expect(controller!.text, 'hello');
      expect(controller!.selection, const TextSelection.collapsed(offset: 5));

      controller!.undo();
      await tester.pump();
      expect(controller!.selection, const TextSelection.collapsed(offset: 0));
    });

    testWidgets('the keyboard shortcuts undo and redo', (tester) async {
      manager.track(CRDTFugueRichTextHandler(doc, 'page'));
      await tester.pumpWidget(host(undoManager: manager));
      await tester.showKeyboard(find.byType(TextField));
      controller!.value = const TextEditingValue(
        text: 'hello',
        selection: TextSelection.collapsed(offset: 5),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.pump();
      expect(controller!.text, '');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();
      expect(controller!.text, 'hello');
      expectInSync('shortcuts');
    });

    testWidgets('undo waits for an IME composition to end', (tester) async {
      manager.track(CRDTFugueRichTextHandler(doc, 'page'));
      await tester.pumpWidget(host(undoManager: manager));
      await tester.showKeyboard(find.byType(TextField));
      controller!.value = const TextEditingValue(
        text: 'hello',
        selection: TextSelection.collapsed(offset: 5),
      );
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'helloX',
          selection: TextSelection.collapsed(offset: 6),
          composing: TextRange(start: 5, end: 6),
        ),
      );
      await tester.pump();

      controller!.undo();
      await tester.pump();

      expect(pageOf(doc).text, 'hello');
      expect(controller!.text, 'helloX');
    });

    testWidgets('a peer edit stays, and the buttons follow the manager', (
      tester,
    ) async {
      manager.track(CRDTFugueRichTextHandler(doc, 'page'));
      await tester.pumpWidget(host(undoManager: manager));
      var notified = 0;
      controller!.addListener(() => notified++);

      final remote = remotePeer();
      pageOf(remote).insert(0, 'peer ');
      syncFrom(remote);
      await tester.pump();
      expect(controller!.canUndo, isFalse);

      controller!.value = const TextEditingValue(
        text: 'peer mine',
        selection: TextSelection.collapsed(offset: 9),
      );
      await tester.pump();
      final before = notified;
      manager.clear();
      await tester.pump();

      expect(controller!.canUndo, isFalse);
      expect(notified, greaterThan(before));
      expect(controller!.text, 'peer mine');
    });

    testWidgets("a write that is not the field's is not recorded", (
      tester,
    ) async {
      final page = CRDTFugueRichTextHandler(doc, 'page');
      manager.track(page);
      await tester.pumpWidget(host(undoManager: manager));

      page.insert(0, 'direct');
      await tester.pump();

      expect(controller!.canUndo, isFalse);
    });
  });

  for (final seed in [7, 13, 29, 101, 997]) {
    testWidgets('tracks a random stream of rich edits (seed $seed)', (
      tester,
    ) async {
      CRDTFugueRichTextHandler(doc, 'page').insert(0, 'hello world');
      await tester.pumpWidget(host());
      final remote = remotePeer();
      final remotePage = pageOf(remote);
      final random = Random(seed);
      var composing = false;

      for (var round = 0; round < 150; round++) {
        final c = controller!;
        final text = c.text;
        switch (random.nextInt(8)) {
          case 0 || 1:
            if (composing) {
              break;
            }
            final at = _runeBoundary(text, random.nextInt(text.length + 1));
            if (random.nextInt(4) == 0) {
              c
                ..selection = TextSelection.collapsed(offset: at)
                ..toggle('bold');
            }
            final typed = random.nextInt(6) == 0
                ? '😀'
                : String.fromCharCode(97 + random.nextInt(26));
            c.value = TextEditingValue(
              text: text.replaceRange(at, at, typed),
              selection: TextSelection.collapsed(offset: at + typed.length),
            );
          case 2:
            if (composing || text.isEmpty) {
              break;
            }
            final at = _runeBoundary(text, random.nextInt(text.length));
            c.value = TextEditingValue(
              text: text.replaceRange(at, _nextRune(text, at), ''),
              selection: TextSelection.collapsed(offset: at),
            );
          case 3:
            if (composing) {
              break;
            }
            composing = true;
            c.value = TextEditingValue(
              text: '${text}zz',
              selection: TextSelection.collapsed(offset: text.length + 2),
              composing: TextRange(start: text.length, end: text.length + 2),
            );
          case 4:
            if (!composing) {
              break;
            }
            composing = false;
            c.value = TextEditingValue(
              text: text,
              selection: TextSelection.collapsed(offset: text.length),
            );
          case 5 || 6:
            if (random.nextBool()) {
              remote.importChanges(
                doc.exportChanges(fromVersionVector: remote.getVersionVector()),
              );
            }
            for (var i = 0; i < 1 + random.nextInt(3); i++) {
              final length = remotePage.length;
              switch (random.nextInt(3)) {
                case 0:
                  remotePage.insert(
                    random.nextInt(length + 1),
                    random.nextInt(6) == 0
                        ? '🎉'
                        : String.fromCharCode(65 + random.nextInt(26)),
                  );
                case 1:
                  if (length > 0) {
                    remotePage.delete(random.nextInt(length), 1);
                  }
                case _:
                  if (length > 0) {
                    final from = random.nextInt(length);
                    remotePage.format(
                      from,
                      1 + random.nextInt(length - from),
                      random.nextBool() ? 'bold' : 'italic',
                      random.nextBool() ? true : null,
                    );
                  }
              }
            }
            syncFrom(remote);
          default:
            if (composing || text.isEmpty) {
              break;
            }
            final a = _runeBoundary(text, random.nextInt(text.length));
            final b =
                _runeBoundary(text, a + 1 + random.nextInt(text.length - a));
            if (b <= a) {
              break;
            }
            c
              ..selection = TextSelection(baseOffset: a, extentOffset: b)
              ..toggle('bold');
        }

        await tester.pumpAndSettle();
        // A remote change commits a pending composition, an empty sync does
        // not.
        composing = controller!.text != controller!.spansText;
        if (!composing) {
          expectInSync('seed $seed round $round');
        }
      }

      if (composing) {
        controller!.value = TextEditingValue(
          text: controller!.text,
          selection: TextSelection.collapsed(offset: controller!.text.length),
        );
        await tester.pumpAndSettle();
      }
      expectInSync('seed $seed end');
    });
  }
}

int _runeBoundary(String text, int offset) {
  if (offset <= 0 || offset >= text.length) {
    return offset.clamp(0, text.length);
  }
  final unit = text.codeUnitAt(offset);
  return (unit >= 0xDC00 && unit <= 0xDFFF) ? offset - 1 : offset;
}

int _nextRune(String text, int at) {
  final unit = text.codeUnitAt(at);
  return (unit >= 0xD800 && unit <= 0xDBFF && at + 1 < text.length)
      ? at + 2
      : at + 1;
}
