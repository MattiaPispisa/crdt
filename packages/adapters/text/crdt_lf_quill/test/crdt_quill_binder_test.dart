// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart' hide ChangeSource;
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_lf_quill/crdt_lf_quill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CRDTDocument document;
  late CRDTFugueRichTextHandler page;

  Widget host(QuillController controller) => CrdtProvider.value(
    value: document,
    child: MaterialApp(
      home: CrdtQuillBinder(
        id: 'page',
        controller: controller,
        builder: (context) => const SizedBox(),
      ),
    ),
  );

  setUp(() {
    document = CRDTDocument(peerId: PeerId.generate());
    page = CRDTFugueRichTextHandler(document, 'page')..insert(0, 'hello');
  });

  tearDown(() => document.dispose());

  testWidgets('keeps the controller and the handler in step', (tester) async {
    final controller = QuillController.basic();
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller));

    expect(controller.document.toPlainText(), 'hello\n');

    controller.replaceText(5, 0, '!', null);
    expect(page.text, 'hello!');

    final remote = CRDTDocument(peerId: PeerId.generate());
    addTearDown(remote.dispose);
    remote.importChanges(document.exportChanges());
    CRDTFugueRichTextHandler(remote, 'page').insert(0, '> ');
    document.importChanges(remote.exportChanges());
    expect(controller.document.toPlainText(), '> hello!\n');
  });

  testWidgets('moves to a new controller', (tester) async {
    final first = QuillController.basic();
    final second = QuillController.basic();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await tester.pumpWidget(host(first));
    await tester.pumpWidget(host(second));

    expect(second.document.toPlainText(), 'hello\n');

    first.replaceText(0, 0, 'old ', null);
    second.replaceText(5, 0, ' world', null);
    expect(page.text, 'hello world');
  });

  Widget withToolbar(QuillController controller, String id) =>
      CrdtProvider.value(
        value: document,
        child: MaterialApp(
          home: Column(
            children: [
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) =>
                    Text(controller.document.toPlainText().trim()),
              ),
              CrdtQuillBinder(
                id: id,
                controller: controller,
                builder: (context) => const SizedBox(),
              ),
            ],
          ),
        ),
      );

  testWidgets('a toolbar above the binder sees the first content', (
    tester,
  ) async {
    final controller = QuillController.basic();
    addTearDown(controller.dispose);
    await tester.pumpWidget(withToolbar(controller, 'page'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(controller.document.toPlainText(), 'hello\n');
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('a toolbar above the binder follows a new id', (tester) async {
    CRDTFugueRichTextHandler(document, 'other').insert(0, 'other page');
    final controller = QuillController.basic();
    addTearDown(controller.dispose);
    await tester.pumpWidget(withToolbar(controller, 'page'));
    await tester.pump();
    await tester.pumpWidget(withToolbar(controller, 'other'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(controller.document.toPlainText(), 'other page\n');
    expect(find.text('other page'), findsOneWidget);

    controller.replaceText(0, 0, '> ', null);
    expect(
      (document.handlerById('other')! as CRDTFugueRichTextHandler).text,
      '> other page',
    );
    expect(page.text, 'hello');
  });

  testWidgets('a change made before the first content shows is kept once', (
    tester,
  ) async {
    final remote = CRDTDocument(peerId: PeerId.generate());
    addTearDown(remote.dispose);
    remote.importChanges(document.exportChanges());
    CRDTFugueRichTextHandler(remote, 'page').insert(0, '> ');
    final controller = QuillController.basic();
    addTearDown(controller.dispose);
    // Runs after the build and before the binder shows the content.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => document.importChanges(remote.exportChanges()),
    );
    await tester.pumpWidget(withToolbar(controller, 'page'));

    expect(tester.takeException(), isNull);
    expect(controller.document.toPlainText(), '> hello\n');

    controller.replaceText(7, 0, '!', null);
    expect(page.text, '> hello!');
  });

  testWidgets('a remote change leaves the focus where it is', (tester) async {
    final bob = CRDTDocument(peerId: PeerId.generate());
    addTearDown(bob.dispose);
    bob.importChanges(document.exportChanges());
    CRDTFugueRichTextHandler(bob, 'page');
    final aliceController = QuillController.basic();
    final bobController = QuillController.basic();
    final aliceFocus = FocusNode();
    final bobFocus = FocusNode();
    addTearDown(aliceController.dispose);
    addTearDown(bobController.dispose);
    addTearDown(aliceFocus.dispose);
    addTearDown(bobFocus.dispose);

    Widget editor(
      CRDTDocument crdt,
      QuillController controller,
      FocusNode focus,
    ) => Expanded(
      child: CrdtProvider.value(
        value: crdt,
        child: CrdtQuillBinder(
          id: 'page',
          controller: controller,
          builder: (context) =>
              QuillEditor.basic(controller: controller, focusNode: focus),
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              editor(document, aliceController, aliceFocus),
              editor(bob, bobController, bobFocus),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(bobController.document.toPlainText(), 'hello\n');
    expect(aliceFocus.hasFocus, isFalse);
    expect(bobFocus.hasFocus, isFalse);

    aliceFocus.requestFocus();
    await tester.pump();
    aliceController.replaceText(5, 0, '!', null);
    bob.importChanges(document.exportChanges());
    // On the web, Alice's own change starts a 500 ms caret timer.
    await tester.pump(const Duration(milliseconds: 500));

    expect(bobController.document.toPlainText(), 'hello!\n');
    expect(aliceFocus.hasFocus, isTrue);
    expect(bobFocus.hasFocus, isFalse);
  });

  testWidgets('stops writing once removed', (tester) async {
    final controller = QuillController.basic();
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller));
    await tester.pumpWidget(const SizedBox());

    controller.replaceText(0, 0, 'x', null);
    expect(page.text, 'hello');
  });
}
