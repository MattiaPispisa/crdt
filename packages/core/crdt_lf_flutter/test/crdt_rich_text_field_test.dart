// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_lf_flutter/src/effects/crdt_rich_text_field.dart'
    show sameRuneAttributes;
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
      supportsEmbeds: true,
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
    String id = 'page',
    CRDTUndoManager? undoManager,
  }) {
    return CrdtProvider.value(
      value: doc,
      child: MaterialApp(
        home: Scaffold(
          body: CrdtRichTextFieldBuilder(
            id: id,
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

  testWidgets('takes in a format written by a watcher inside a push', (
    tester,
  ) async {
    debugVerifyCrdtRichTextFieldProjection = false;
    addTearDown(() => debugVerifyCrdtRichTextFieldProjection = true);
    final page = CRDTFugueRichTextHandler(doc, 'page')..insert(0, 'hello');
    var armed = true;
    final watcher = page.watch().listen((_) {
      if (armed && page.text == 'helloX') {
        armed = false;
        page.format(0, 2, 'bold', true);
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
    expectInSync('after the watcher');
  });

  testWidgets('takes in an embed update written by a watcher inside a push', (
    tester,
  ) async {
    debugVerifyCrdtRichTextFieldProjection = false;
    addTearDown(() => debugVerifyCrdtRichTextFieldProjection = true);
    final page = CRDTFugueRichTextHandler(doc, 'page')
      ..insert(0, 'hello')
      ..insertEmbed(0, {'image': 'a.png'});
    var armed = true;
    final watcher = page.watch().listen((_) {
      if (armed && page.text == '\uFFFChelloX') {
        armed = false;
        page.updateEmbed(0, {'image': 'b.png'});
      }
    });
    addTearDown(watcher.cancel);
    await tester.pumpWidget(host());
    controller!.value = const TextEditingValue(
      text: '\uFFFChelloX',
      selection: TextSelection.collapsed(offset: 7),
    );
    await tester.pumpAndSettle();

    expect(armed, isFalse);
    expect(embedsOf(controller!.spans), [
      {'image': 'b.png'},
    ]);
  });

  testWidgets('a styled keystroke and a format are their own echo', (
    tester,
  ) async {
    debugVerifyCrdtRichTextFieldProjection = false;
    addTearDown(() => debugVerifyCrdtRichTextFieldProjection = true);
    final page = _CountingPage(doc, 'page')..insert(0, 'hello');
    await tester.pumpWidget(host());
    controller!.selection = const TextSelection.collapsed(offset: 5);
    controller!.format('link', 'https://a.b', expand: MarkExpand.none);
    controller!.toggle('bold');
    page.reads = 0;

    controller!.value = const TextEditingValue(
      text: 'helloX',
      selection: TextSelection.collapsed(offset: 6),
    );
    await tester.pump();
    expect(page.attributesAt(5), {'bold': true, 'link': 'https://a.b'});
    expect(page.reads, 0);

    controller!.selection = const TextSelection(baseOffset: 0, extentOffset: 2);
    controller!.toggle('italic');
    await tester.pump();
    // The field reads the formats once, after the write.
    expect(page.reads, 1);
    expectInSync('own formats');
  });

  testWidgets('an embed is painted as U+FFFC and follows remote updates', (
    tester,
  ) async {
    CRDTFugueRichTextHandler(doc, 'page')
      ..insert(0, 'ab')
      ..insertEmbed(1, {'image': 'a.png'}, attributes: {'bold': true});
    await tester.pumpWidget(host());
    final editable = tester.allRenderObjects.whereType<RenderEditable>().first;
    expect(editable.text!.toPlainText(), 'a\uFFFCb');
    expect(paintedStyleAt(tester, 1)?.fontWeight, FontWeight.bold);

    controller!.value = const TextEditingValue(
      text: 'aX\uFFFCb',
      selection: TextSelection.collapsed(offset: 2),
    );
    await tester.pump();
    final remote = remotePeer();
    pageOf(remote).updateEmbed(2, {'image': 'b.png'});
    syncFrom(remote);
    await tester.pump();

    expect(embedsOf(controller!.spans), [
      {'image': 'b.png'},
    ]);
    expect(controller!.selection, const TextSelection.collapsed(offset: 2));
    expectInSync('updated embed');
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

  testWidgets('a U+FFFC stripped from a composition keeps it in place', (
    tester,
  ) async {
    CRDTFugueRichTextHandler(doc, 'page').insert(0, 'hello');
    await tester.pumpWidget(host());
    await tester.showKeyboard(find.byType(TextField));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'ha\uFFFCbello',
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange(start: 1, end: 4),
      ),
    );
    await tester.pump();
    expect(pageOf(doc).text, 'hello');

    // A remote change commits the composition, without the U+FFFC.
    final remote = remotePeer();
    pageOf(remote).insert(0, 'Z');
    syncFrom(remote);
    await tester.pump();

    expect(pageOf(doc).text, 'Zhabello');
    expect(controller!.text, 'Zhabello');
    expect(controller!.selection, const TextSelection.collapsed(offset: 4));
    expect(controller!.value.composing, const TextRange(start: 2, end: 4));
  });

  group('a value set with edits on both sides of an embed', () {
    testWidgets('keeps the embed, and the write is its own echo', (
      tester,
    ) async {
      debugVerifyCrdtRichTextFieldProjection = false;
      addTearDown(() => debugVerifyCrdtRichTextFieldProjection = true);
      final page = _CountingPage(doc, 'page')
        ..insert(0, 'ab')
        ..insertEmbed(1, {'image': 'a.png'});
      await tester.pumpWidget(host());
      controller!.selection = const TextSelection.collapsed(offset: 0);
      controller!.toggle('bold');
      page.reads = 0;

      controller!.value = const TextEditingValue(
        text: 'Xa\uFFFCbY',
        selection: TextSelection.collapsed(offset: 5),
      );
      await tester.pump();

      expect(page.reads, 0);
      expect(page.text, 'Xa\uFFFCbY');
      expect(page.attributesAt(0), {'bold': true});
      expect(page.attributesAt(4), isEmpty);
      expect(embedsOf(page.value), [
        {'image': 'a.png'},
      ]);
      expect(controller!.selection, const TextSelection.collapsed(offset: 5));
      expectInSync('embed kept');
    });

    testWidgets('keeps every embed it does not delete', (tester) async {
      CRDTFugueRichTextHandler(doc, 'page')
        ..insert(0, 'abc')
        ..insertEmbed(2, {'image': 'b.png'})
        ..insertEmbed(1, {'image': 'a.png'});
      await tester.pumpWidget(host());
      expect(controller!.text, 'a\uFFFCb\uFFFCc');

      controller!.value = const TextEditingValue(
        text: 'Xa\uFFFCbZ\uFFFCcY',
        selection: TextSelection.collapsed(offset: 8),
      );
      await tester.pump();
      expect(pageOf(doc).text, 'Xa\uFFFCbZ\uFFFCcY');
      expect(embedsOf(pageOf(doc).value), [
        {'image': 'a.png'},
        {'image': 'b.png'},
      ]);

      controller!.value = const TextEditingValue(
        text: 'WXab\uFFFCcYV',
        selection: TextSelection.collapsed(offset: 8),
      );
      await tester.pump();
      expect(pageOf(doc).text, 'WXab\uFFFCcYV');
      expect(embedsOf(pageOf(doc).value), [
        {'image': 'b.png'},
      ]);
      expectInSync('one embed deleted');
    });

    testWidgets('strips a pasted U+FFFC', (tester) async {
      CRDTFugueRichTextHandler(doc, 'page')
        ..insert(0, 'ab')
        ..insertEmbed(1, {'image': 'a.png'});
      await tester.pumpWidget(host());

      controller!.value = const TextEditingValue(
        text: 'X\uFFFCa\uFFFCbY',
        selection: TextSelection(baseOffset: 1, extentOffset: 6),
      );
      await tester.pump();

      expect(pageOf(doc).text, 'Xa\uFFFCbY');
      expect(embedsOf(pageOf(doc).value), [
        {'image': 'a.png'},
      ]);
      expect(
        controller!.selection,
        const TextSelection(baseOffset: 1, extentOffset: 5),
      );
      expectInSync('pasted U+FFFC stripped');
    });

    testWidgets('keeps the embed when a remote change commits it', (
      tester,
    ) async {
      CRDTFugueRichTextHandler(doc, 'page')
        ..insert(0, 'ab')
        ..insertEmbed(1, {'image': 'a.png'});
      await tester.pumpWidget(host());
      await tester.showKeyboard(find.byType(TextField));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'Xa\uFFFCbY',
          selection: TextSelection.collapsed(offset: 5),
          composing: TextRange(start: 4, end: 5),
        ),
      );
      await tester.pump();

      final remote = remotePeer();
      pageOf(remote).insert(1, 'Z');
      syncFrom(remote);
      await tester.pump();

      expect(pageOf(doc).text, 'XaZ\uFFFCbY');
      expect(embedsOf(pageOf(doc).value), [
        {'image': 'a.png'},
      ]);
      expectInSync('composition committed');
    });

    testWidgets('a replacement with no embed in it stays one region', (
      tester,
    ) async {
      CRDTFugueRichTextHandler(doc, 'page')
        ..insert(0, 'abc')
        ..format(1, 1, 'bold', true)
        ..insertEmbed(3, {'image': 'a.png'});
      await tester.pumpWidget(host());

      controller!.value = const TextEditingValue(
        text: 'xbz\uFFFC',
        selection: TextSelection.collapsed(offset: 3),
      );
      await tester.pump();

      expect(pageOf(doc).attributesAt(1), isEmpty);
      expectInSync('retyped');
    });

    testWidgets('takes in a write served inside the push', (tester) async {
      debugVerifyCrdtRichTextFieldProjection = false;
      addTearDown(() => debugVerifyCrdtRichTextFieldProjection = true);
      final page = CRDTFugueRichTextHandler(doc, 'page')
        ..insert(0, 'ab')
        ..insertEmbed(1, {'image': 'a.png'});
      var armed = true;
      final watcher = page.watch().listen((_) {
        if (armed && page.text == 'Xa\uFFFCbY') {
          armed = false;
          page
            ..delete(1, 1)
            ..insert(1, 'A');
        }
      });
      addTearDown(watcher.cancel);
      await tester.pumpWidget(host());

      controller!.value = const TextEditingValue(
        text: 'Xa\uFFFCbY',
        selection: TextSelection.collapsed(offset: 5),
      );
      await tester.pumpAndSettle();

      expect(armed, isFalse);
      expect(page.text, 'XA\uFFFCbY');
      expectInSync('after the watcher');
    });
  });

  testWidgets('a delete served inside a push leaves the field on the handler', (
    tester,
  ) async {
    debugVerifyCrdtRichTextFieldProjection = false;
    addTearDown(() => debugVerifyCrdtRichTextFieldProjection = true);
    final page = CRDTFugueRichTextHandler(doc, 'page')..insert(0, 'hello');
    var armed = true;
    final watcher = page.watch().listen((_) {
      if (armed && page.text == 'helloX') {
        armed = false;
        page.delete(5, 1);
      }
    });
    addTearDown(watcher.cancel);
    await tester.pumpWidget(host());

    controller!.value = const TextEditingValue(
      text: 'helloX',
      selection: TextSelection.collapsed(offset: 6),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(armed, isFalse);
    expect(page.text, 'hello');
    expectInSync('after the delete');
  });

  testWidgets('a delete served inside a two-region push too', (tester) async {
    debugVerifyCrdtRichTextFieldProjection = false;
    addTearDown(() => debugVerifyCrdtRichTextFieldProjection = true);
    final page = CRDTFugueRichTextHandler(doc, 'page')
      ..insert(0, 'ab')
      ..insertEmbed(1, {'image': 'a.png'});
    var armed = true;
    final watcher = page.watch().listen((_) {
      if (armed && page.text == 'Xa\uFFFCbY') {
        armed = false;
        page.delete(4, 1);
      }
    });
    addTearDown(watcher.cancel);
    await tester.pumpWidget(host());

    controller!.value = const TextEditingValue(
      text: 'Xa\uFFFCbY',
      selection: TextSelection.collapsed(offset: 5),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(page.text, 'Xa\uFFFCb');
    expectInSync('after the delete');
  });

  group('a composition commits over a remote embed in its range', () {
    // Pinned: the embed has to survive the commit on both sides.
    final local = PeerId.parse('00000000-0000-4000-8000-00000000000a');
    final peer = PeerId.parse('00000000-0000-4000-8000-00000000000b');

    Future<void> commitOver(
      WidgetTester tester, {
      required int at,
      required String expected,
    }) async {
      doc = CRDTDocument(peerId: local);
      final page = CRDTFugueRichTextHandler(doc, 'page')..insert(0, 'teh');
      await tester.pumpWidget(host());
      await tester.showKeyboard(find.byType(TextField));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'the',
          selection: TextSelection.collapsed(offset: 3),
          composing: TextRange(start: 0, end: 3),
        ),
      );
      await tester.pump();

      final remote = CRDTDocument(peerId: peer);
      final remotePage = CRDTFugueRichTextHandler(remote, 'page');
      remote.importChanges(doc.exportChanges());
      remotePage.insertEmbed(at, {'image': 'a.png'});
      syncFrom(remote);
      await tester.pump();

      remote.importChanges(
        doc.exportChanges(fromVersionVector: remote.getVersionVector()),
      );
      expect(page.text, expected);
      expect(remotePage.text, expected);
      expect(embedsOf(page.value), [
        {'image': 'a.png'},
      ]);
      expectInSync('committed');
    }

    testWidgets('at its start', (tester) async {
      await commitOver(tester, at: 1, expected: 't\uFFFChe');
    });

    testWidgets('inside it', (tester) async {
      await commitOver(tester, at: 2, expected: 'the\uFFFC');
    });
  });

  testWidgets('a value the handler refuses throws at format', (tester) async {
    CRDTFugueRichTextHandler(doc, 'page').insert(0, 'hlo');
    await tester.pumpWidget(host());
    controller!.selection = const TextSelection.collapsed(offset: 1);

    expect(() => controller!.format('w', const [1]), throwsArgumentError);
    expect(controller!.pendingAttributes, isEmpty);

    controller!.value = const TextEditingValue(
      text: 'hXlo',
      selection: TextSelection.collapsed(offset: 2),
    );
    await tester.pump();

    expect(pageOf(doc).text, 'hXlo');
    expectInSync('typed');
  });

  testWidgets('the style set at a caret stays behind on a change of handler', (
    tester,
  ) async {
    CRDTFugueRichTextHandler(doc, 'page').insert(0, 'hello');
    final other = CRDTFugueRichTextHandler(doc, 'other')..insert(0, 'world');
    await tester.pumpWidget(host());
    controller!.selection = const TextSelection.collapsed(offset: 0);
    controller!.format('bold', true);

    await tester.pumpWidget(host(id: 'other'));
    expect(controller!.pendingAttributes, isEmpty);

    controller!.value = const TextEditingValue(
      text: 'Qworld',
      selection: TextSelection.collapsed(offset: 1),
    );
    await tester.pump();

    expect(other.value, [RichTextSpan('Qworld')]);
  });

  testWidgets('the attributes of the caret are read-only', (tester) async {
    CRDTFugueRichTextHandler(doc, 'page');
    await tester.pumpWidget(host());

    expect(
      () => (controller! as dynamic).pendingAttributes = {'bold': true},
      throwsNoSuchMethodError,
    );
  });

  testWidgets('a wrong handler is refused in the name of the field', (
    tester,
  ) async {
    CRDTFugueTextHandler(doc, 'page');
    await tester.pumpWidget(host());

    expect(
      tester.takeException().toString(),
      contains('CrdtRichTextFieldBuilder'),
    );
  });

  testWidgets('anchors are withdrawn while an IME composition is pending', (
    tester,
  ) async {
    CRDTFugueRichTextHandler(doc, 'page').insert(0, 'hello');
    await tester.pumpWidget(host());
    await tester.showKeyboard(find.byType(TextField));
    controller!.selection = const TextSelection.collapsed(offset: 5);
    await tester.pump();
    expect(anchors.last.$1, isNotNull);

    controller!.value = const TextEditingValue(
      text: 'helloあ',
      selection: TextSelection.collapsed(offset: 6),
      composing: TextRange(start: 5, end: 6),
    );
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

  testWidgets('reads the format a selection shares, emoji included', (
    tester,
  ) async {
    CRDTFugueRichTextHandler(doc, 'page')
      ..insert(0, 'a\u{1F600}bcd')
      ..format(0, 2, 'bold', true)
      ..format(3, 1, 'bold', true);
    await tester.pumpWidget(host());
    Object? boldOver(int start, int end) {
      controller!.selection = TextSelection(
        baseOffset: start,
        extentOffset: end,
      );
      return controller!.attributeAtSelection('bold');
    }

    // In code units: 'a' 0..1 and the emoji 1..3 are bold, 'b' 3..4 is
    // plain, 'c' 4..5 is bold, 'd' 5..6 is plain.
    expect(boldOver(0, 3), isTrue);
    expect(boldOver(1, 3), isTrue);
    expect(boldOver(4, 5), isTrue);
    expect(boldOver(0, 5), isNull);
    expect(boldOver(3, 5), isNull);
  });

  testWidgets('the style set at a caret keeps its expand mode', (
    tester,
  ) async {
    CRDTFugueRichTextHandler(doc, 'page').insert(0, 'hello');
    await tester.pumpWidget(host());
    controller!.selection = const TextSelection.collapsed(offset: 5);
    controller!.format('link', 'https://a.b', expand: MarkExpand.none);
    controller!.value = const TextEditingValue(
      text: 'helloX',
      selection: TextSelection.collapsed(offset: 6),
    );
    await tester.pump();
    expect(pageOf(doc).attributesAt(5), {'link': 'https://a.b'});

    // Typed after the link, by this peer or another: it must stay plain.
    pageOf(doc).insert(6, 'Y');
    await tester.pump();

    expect(pageOf(doc).attributesAt(6), isEmpty);
    expectInSync('after the link');
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

    testWidgets('an undo that changes nothing leaves the caret', (
      tester,
    ) async {
      manager.track(CRDTFugueRichTextHandler(doc, 'page'));
      pageOf(doc).insert(0, 'hello world');
      await tester.pumpWidget(host(undoManager: manager));
      controller!.value = const TextEditingValue(
        text: 'hello world!!',
        selection: TextSelection.collapsed(offset: 13),
      );
      await tester.pump();

      final remote = remotePeer();
      pageOf(remote).delete(11, 2);
      syncFrom(remote);
      await tester.pump();
      controller!.selection = const TextSelection.collapsed(offset: 8);

      controller!.undo();
      await tester.pump();

      expect(controller!.text, 'hello world');
      expect(controller!.selection, const TextSelection.collapsed(offset: 8));
    });

    testWidgets('typing after a format is a step of its own', (tester) async {
      manager.track(CRDTFugueRichTextHandler(doc, 'page'));
      pageOf(doc).insert(0, 'hello');
      await tester.pumpWidget(host(undoManager: manager));
      controller!
        ..selection = const TextSelection(baseOffset: 0, extentOffset: 5)
        ..toggle('bold');
      controller!.value = const TextEditingValue(
        text: 'hello!',
        selection: TextSelection.collapsed(offset: 6),
      );
      await tester.pump();

      controller!.undo();
      await tester.pump();

      expect(pageOf(doc).value, [
        RichTextSpan('hello', {'bold': true}),
      ]);
      expectInSync('typing undone');
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

    testWidgets('a manager passed later keeps the field mounted', (
      tester,
    ) async {
      manager.track(CRDTFugueRichTextHandler(doc, 'page'));
      await tester.pumpWidget(host());
      await tester.showKeyboard(find.byType(TextField));
      final before = tester.state(find.byType(EditableText));

      await tester.pumpWidget(host(undoManager: manager));

      expect(tester.state(find.byType(EditableText)), same(before));
      expect(FocusManager.instance.primaryFocus?.hasFocus, isTrue);
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

    testWidgets('undo brings a deleted embed back with its data', (
      tester,
    ) async {
      final page = CRDTFugueRichTextHandler(doc, 'page')
        ..insert(0, 'ab')
        ..insertEmbed(1, {'image': 'a.png'});
      manager.track(page);
      await tester.pumpWidget(host(undoManager: manager));

      controller!.value = const TextEditingValue(
        text: 'ab',
        selection: TextSelection.collapsed(offset: 1),
      );
      await tester.pump();
      expect(page.text, 'ab');

      controller!.undo();
      await tester.pump();
      expect(controller!.text, 'a\uFFFCb');
      expect(embedsOf(controller!.spans), [
        {'image': 'a.png'},
      ]);
      expectInSync('embed restored');

      controller!.redo();
      await tester.pump();
      expect(controller!.text, 'ab');
      expectInSync('embed deleted again');
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

List<Map<String, Object?>> embedsOf(List<RichTextSpan> spans) => [
      for (final span in spans)
        if (span.embed != null) span.embed!,
    ];

base class _CountingPage extends CRDTFugueRichTextHandler {
  _CountingPage(super.doc, super.id);

  int reads = 0;

  @override
  List<RichTextSpan> get value {
    reads++;
    return super.value;
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
