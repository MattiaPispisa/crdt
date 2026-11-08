// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:crdt_lf_recipes/flutter_note/note_page.dart';
import 'package:flutter/material.dart';
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

  setUpAll(CRDTHive.initialize);

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('flutter_note');
    Hive.init(directory.path);
    backend = await CRDTHive.open();
  });

  tearDown(() async {
    await CRDTHive.closeAllBoxes();
    directory.deleteSync(recursive: true);
  });

  testWidgets('the note survives a restart', (tester) async {
    final field = find.byType(TextField);
    final changesBox = documentBoxNameFor('changes', 'note');

    // The page opens the note in initState: run it with the real IO.
    await tester.runAsync(
      () => tester.pumpWidget(MaterialApp(home: NotePage(backend: backend))),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await pumpUntil(tester, () => field.evaluate().isNotEmpty);

    await tester.enterText(field, 'Hello');

    // Removing the page closes the note, and its storage last.
    await tester.runAsync(() => tester.pumpWidget(const SizedBox()));
    await pumpUntil(tester, () => !Hive.isBoxOpen(changesBox));

    await tester.runAsync(
      () => tester.pumpWidget(MaterialApp(home: NotePage(backend: backend))),
    );
    await pumpUntil(tester, () => field.evaluate().isNotEmpty);

    expect(find.text('Hello'), findsOneWidget);

    await tester.runAsync(() => tester.pumpWidget(const SizedBox()));
    await pumpUntil(tester, () => !Hive.isBoxOpen(changesBox));
  });
}
