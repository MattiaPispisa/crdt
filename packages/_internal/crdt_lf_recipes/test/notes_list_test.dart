// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:io';

import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:crdt_lf_recipes/notes_list/notes_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'helpers.dart';

// Fake time too, so the route transitions end.
const _step = Duration(milliseconds: 50);

void main() {
  late Directory directory;
  late CRDTHiveBackend backend;

  final field = find.byType(TextField);
  final list = find.byType(ListView);

  setUpAll(CRDTHive.initialize);

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('notes_list');
    Hive.init(directory.path);
    backend = await CRDTHive.open();
  });

  tearDown(() async {
    await CRDTHive.closeAllBoxes();
    directory.deleteSync(recursive: true);
  });

  /// Adds a note that reads [text], and goes back to the list.
  Future<void> addNote(WidgetTester tester, String text) async {
    await tester.tap(find.byType(FloatingActionButton));
    await pumpUntil(tester, () => field.evaluate().isNotEmpty, step: _step);
    await tester.enterText(field, text);

    await tester.pageBack();
    // The title shows once the note is closed and the list reloaded.
    final title = text.split('\n').first;
    await pumpUntil(
      tester,
      () =>
          find
              .descendant(of: list, matching: find.text(title))
              .evaluate()
              .isNotEmpty,
      step: _step,
    );
  }

  testWidgets('lists, deletes and reopens the notes', (tester) async {
    await tester.runAsync(
      () => tester.pumpWidget(MaterialApp(home: NotesPage(backend: backend))),
    );
    await pumpUntil(tester, () => list.evaluate().isNotEmpty, step: _step);

    await addNote(tester, 'Groceries\nmilk, eggs');
    await addNote(tester, 'Ideas\na recipe app');
    expect(find.byType(ListTile), findsNWidgets(2));
    expect(await tester.runAsync(() => backend.documentIds), hasLength(2));

    // Swipe the first note away.
    await tester.drag(find.text('Groceries'), const Offset(-800, 0));
    await pumpUntil(
      tester,
      () => find.text('Groceries').evaluate().isEmpty,
      step: _step,
    );
    expect(find.byType(ListTile), findsOneWidget);
    // The delete runs after the row is gone.
    var ids = <String>{};
    await pumpUntil(
      tester,
      () => ids.length == 1,
      poll: () async {
        ids = await backend.documentIds;
      },
      step: _step,
    );

    // The other note opens with its text.
    await tester.tap(find.text('Ideas'));
    await pumpUntil(tester, () => field.evaluate().isNotEmpty, step: _step);
    expect(find.text('Ideas\na recipe app'), findsOneWidget);

    // A new title proves the note was written, closed and read again.
    await tester.enterText(field, 'Ideas for later\na recipe app');
    await tester.pageBack();
    await pumpUntil(
      tester,
      () => find.text('Ideas for later').evaluate().isNotEmpty,
      step: _step,
    );

    // Edit, leave, and swipe the note away while it still closes.
    await tester.tap(find.text('Ideas for later'));
    await pumpUntil(tester, () => field.evaluate().isNotEmpty, step: _step);
    await tester.enterText(field, 'Ideas, last edit');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.drag(find.text('Ideas for later'), const Offset(-800, 0));
    await pumpUntil(
      tester,
      () => ids.isEmpty,
      poll: () async {
        ids = await backend.documentIds;
      },
      step: _step,
    );
    // The reload after the close leaves the deleted note out.
    await pumpUntil(
      tester,
      () => find.byType(ListTile).evaluate().isEmpty,
      step: _step,
    );

    await tester.runAsync(() => tester.pumpWidget(const SizedBox()));

    // The pages opened their boxes in the test zone: close them here, while
    // it is still pumped, or the close in tearDown waits forever.
    var closed = false;
    unawaited(CRDTHive.closeAllBoxes().then((_) => closed = true));
    await pumpUntil(tester, () => closed, step: _step);
  });
}
