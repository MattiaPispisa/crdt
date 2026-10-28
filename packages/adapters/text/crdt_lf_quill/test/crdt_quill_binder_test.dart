// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
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

  testWidgets('stops writing once removed', (tester) async {
    final controller = QuillController.basic();
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller));
    await tester.pumpWidget(const SizedBox());

    controller.replaceText(0, 0, 'x', null);
    expect(page.text, 'hello');
  });
}
