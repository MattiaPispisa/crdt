// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_lf_recipes/note_history/history_page.dart';
import 'package:crdt_lf_recipes/note_history/main.dart' as app;
import 'package:crdt_lf_recipes/note_history/note_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// The text the history page shows.
  String previewOf(WidgetTester tester) {
    return tester
        .widget<Text>(
          find.descendant(
            of: find.byType(NotePreview),
            matching: find.byType(Text),
          ),
        )
        .data!;
  }

  testWidgets('the history shows the note after each change', (tester) async {
    app.main();
    await tester.pump();
    final document = CrdtProvider.of(tester.element(find.byType(NotePage)));

    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.enterText(find.byType(TextField), 'Hello world');
    final changes = document.exportChanges().length;

    await tester.tap(find.byTooltip('History'));
    await tester.pumpAndSettle();
    expect(previewOf(tester), 'Hello world');
    expect(find.text('Change $changes of $changes'), findsOneWidget);
    expect(find.textContaining('You · '), findsOneWidget);

    await tester.tap(find.byTooltip('Previous'));
    await tester.pump();
    expect(previewOf(tester), 'Hello');

    // What a drag of the slider to its start reports.
    tester.widget<Slider>(find.byType(Slider)).onChanged!(0);
    await tester.pump();
    expect(previewOf(tester), isEmpty);
    expect(find.text('Before the first change'), findsOneWidget);

    await tester.tap(find.byTooltip('Next'));
    await tester.pump();
    expect(previewOf(tester), 'Hello');

    // An edit made after the history opened does not reach it.
    document.handler(CRDTFugueTextHandler.spec, 'note').insert(0, 'Later: ');
    await tester.pump();
    expect(previewOf(tester), 'Hello');
  });

  test('a change of another peer names its author', () {
    final alice = CRDTDocument();
    final bob = CRDTDocument(
      peerId: PeerId.parse('00000000-0000-4000-8000-000000000002'),
    );
    addTearDown(alice.dispose);
    addTearDown(bob.dispose);

    CRDTFugueTextHandler(bob, 'note').insert(0, 'From Bob');
    alice.importChanges(bob.exportChanges());
    CRDTFugueTextHandler(alice, 'note').insert(0, 'From Alice. ');

    final session = alice.toTimeTravel();
    addTearDown(session.dispose);
    final labels = <String>[];
    for (var cursor = 0; cursor <= session.length; cursor++) {
      session.jump(cursor);
      labels.add(describeChange(session));
    }

    expect(labels.first, 'Before the first change');
    expect(labels, contains(startsWith('You · ')));
    expect(labels, contains(startsWith('00000000 · ')));
  });
}
