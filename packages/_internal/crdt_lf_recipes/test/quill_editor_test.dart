// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:crdt_lf/crdt_lf.dart' hide ChangeSource;
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:crdt_lf_recipes/quill_editor/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// Pumps until [done] holds, letting the real Hive IO run in between.
Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
  var rounds = 0;
  do {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    // A duration, so the timers due now run too.
    await tester.pump(Duration.zero);
  } while (!done() && ++rounds < 200);
  expect(done(), isTrue);
}

void main() {
  late Directory directory;
  late CRDTHiveBackend backend;

  final editor = find.byType(QuillEditor);
  final changesBox = documentBoxNameFor('changes', 'page');

  setUpAll(CRDTHive.initialize);

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('quill_editor');
    Hive.init(directory.path);
    backend = await CRDTHive.open();
  });

  tearDown(() async {
    await CRDTHive.closeAllBoxes();
    directory.deleteSync(recursive: true);
  });

  /// Opens the app, and waits for the editor.
  Future<void> openApp(WidgetTester tester) async {
    // The page opens the document in initState: run it with the real IO.
    await tester.runAsync(() => tester.pumpWidget(EditorApp(backend: backend)));
    await pumpUntil(tester, () => editor.evaluate().isNotEmpty);
  }

  /// Closes the app, and waits for its storage to close.
  Future<void> closeApp(WidgetTester tester) async {
    await tester.runAsync(() => tester.pumpWidget(const SizedBox()));
    await pumpUntil(tester, () => !Hive.isBoxOpen(changesBox));
  }

  QuillController controllerOf(WidgetTester tester) {
    return tester.widget<QuillEditor>(editor).controller;
  }

  CRDTFugueRichTextHandler handlerOf(WidgetTester tester) {
    return tester
        .element(editor)
        .read<CRDTDocument>()
        .handler(CRDTFugueRichTextHandler.spec, 'page');
  }

  testWidgets('writes edits and formats to the handler, and undoes them', (
    tester,
  ) async {
    await openApp(tester);
    final controller = controllerOf(tester);
    final handler = handlerOf(tester);

    controller
      ..replaceText(0, 0, 'Hello', const TextSelection.collapsed(offset: 5))
      ..formatText(0, 5, Attribute.bold);
    await tester.pump();

    expect(handler.value, [
      RichTextSpan('Hello', {'bold': true}),
    ]);

    // A format is a step of its own.
    controller.undo();
    await tester.pump();
    expect(handler.value, [RichTextSpan('Hello')]);

    controller.undo();
    await tester.pump();
    expect(handler.text, isEmpty);

    controller
      ..redo()
      ..redo();
    await tester.pump();
    expect(handler.value, [
      RichTextSpan('Hello', {'bold': true}),
    ]);

    await closeApp(tester);
  });

  testWidgets('the page survives a restart', (tester) async {
    await openApp(tester);
    controllerOf(tester)
      ..replaceText(0, 0, 'Hello', const TextSelection.collapsed(offset: 5))
      ..formatText(0, 5, Attribute.bold);
    await tester.pump();
    await closeApp(tester);

    await openApp(tester);
    expect(controllerOf(tester).document.toPlainText(), 'Hello\n');
    expect(handlerOf(tester).value, [
      RichTextSpan('Hello', {'bold': true}),
    ]);
    await closeApp(tester);
  });
}
