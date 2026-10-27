// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_flutter_demo/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reads the rebuild count shown by the `_RebuildBadge` labelled [label]
/// (its text is "⟳ <label> ×N").
int rebuilds(WidgetTester tester, String label) {
  final text = tester.widget<Text>(find.byKey(Key('rebuilds-$label'))).data!;
  return int.parse(text.split('×').last);
}

Future<void> tapButton(WidgetTester tester, String label) async {
  final finder = find.widgetWithText(FilledButton, label);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('only the widgets that observe a handler re-render', (
    tester,
  ) async {
    // A tall surface so every card is laid out and hit-testable.
    tester.view.physicalSize = const Size(1400, 4200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const CrdtApp());
    await tester.pumpAndSettle();

    final labels = [
      'document',
      'doc-handlers',
      'counter',
      'listener-child',
      'todos-count',
      'todos-list',
      'delta-child',
      'delta-builder',
      'settings-flat',
      'settings-nested',
      'note-text',
      'presence',
    ];
    Map<String, int> snapshot() => {
      for (final l in labels) l: rebuilds(tester, l),
    };

    // 1. Increment the counter → only counter (+ document baseline) rebuilds.
    //    The listener fires its side effect (SnackBar) without rebuilding its
    //    child, and the document-level selector deduplicates.
    var before = snapshot();
    await tapButton(tester, 'Increment');
    expect(rebuilds(tester, 'counter'), before['counter']! + 1);
    expect(rebuilds(tester, 'document'), greaterThan(before['document']!));
    expect(rebuilds(tester, 'doc-handlers'), before['doc-handlers']);
    expect(rebuilds(tester, 'listener-child'), before['listener-child']);
    expect(rebuilds(tester, 'todos-count'), before['todos-count']);
    expect(rebuilds(tester, 'todos-list'), before['todos-list']);
    expect(rebuilds(tester, 'settings-flat'), before['settings-flat']);
    expect(rebuilds(tester, 'settings-nested'), before['settings-nested']);
    expect(rebuilds(tester, 'note-text'), before['note-text']);
    expect(find.text('counter changed → 1'), findsOneWidget);

    // 2. Add a todo → todos count + list rebuild, counter/settings do not.
    before = snapshot();
    await tapButton(tester, 'Add');
    expect(rebuilds(tester, 'todos-count'), before['todos-count']! + 1);
    expect(rebuilds(tester, 'todos-list'), before['todos-list']! + 1);
    expect(rebuilds(tester, 'counter'), before['counter']);
    expect(rebuilds(tester, 'settings-flat'), before['settings-flat']);
    expect(find.text('Todo #1'), findsOneWidget);
    // The delta listener reported the insertion without rebuilding its child,
    // and its own copy of the list followed along.
    expect(rebuilds(tester, 'delta-child'), before['delta-child']);
    expect(find.textContaining('SeqInsert([Todo #1])'), findsOneWidget);
    expect(find.textContaining('1 items'), findsOneWidget);
    // The delta builder did the opposite: one rebuild, with the value it was
    // handed already carrying the insertion.
    expect(rebuilds(tester, 'delta-builder'), before['delta-builder']! + 1);
    expect(find.text('now: Todo #1'), findsOneWidget);

    // 3. Edit the first todo in place → list rebuilds, count does NOT
    //    (its length is unchanged — the selector deduplicates).
    before = snapshot();
    await tapButton(tester, 'Edit first');
    expect(rebuilds(tester, 'todos-list'), before['todos-list']! + 1);
    expect(rebuilds(tester, 'todos-count'), before['todos-count']);

    // 4. Edit the nested nickname → only nested:true rebuilds.
    before = snapshot();
    await tapButton(tester, 'Edit nickname');
    expect(rebuilds(tester, 'settings-nested'), before['settings-nested']! + 1);
    expect(rebuilds(tester, 'settings-flat'), before['settings-flat']);
    expect(rebuilds(tester, 'counter'), before['counter']);
    expect(rebuilds(tester, 'todos-list'), before['todos-list']);

    // 5. Add a key to the container → both nested and flat rebuild, and the
    //    document-level selector bumps: a new handler was registered.
    //    "Remove key" only removes keys added here (nickname is protected),
    //    so it starts disabled and enables reactively with the first add.
    FilledButton removeKey() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Remove key'),
    );
    expect(removeKey().enabled, isFalse);
    before = snapshot();
    await tapButton(tester, 'Add key');
    expect(rebuilds(tester, 'settings-flat'), before['settings-flat']! + 1);
    expect(rebuilds(tester, 'settings-nested'), before['settings-nested']! + 1);
    expect(rebuilds(tester, 'doc-handlers'), before['doc-handlers']! + 1);
    expect(removeKey().enabled, isTrue);

    // 5b. Remove and re-add a key: the map key is reused but the handler id
    //     must not collide with the never-unregistered previous one. The
    //     remove actually shrinks the map (and disables the button again).
    await tapButton(tester, 'Remove key');
    expect(find.text('nested: false → 1 keys'), findsOneWidget);
    expect(removeKey().enabled, isFalse);
    await tapButton(tester, 'Add key');
    expect(find.text('nested: false → 2 keys'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 6. Type into the note field → the handler receives the edit, but
    //    note-text NEVER rebuilds: CrdtTextFieldBuilder drives the controller
    //    directly. Only the document baseline moves.
    before = snapshot();
    await tester.enterText(find.byKey(const Key('note-field')), 'hello world');
    await tester.pumpAndSettle();
    expect(rebuilds(tester, 'note-text'), before['note-text']);
    expect(rebuilds(tester, 'document'), greaterThan(before['document']!));
    expect(rebuilds(tester, 'counter'), before['counter']);
    expect(rebuilds(tester, 'todos-list'), before['todos-list']);
    expect(rebuilds(tester, 'settings-nested'), before['settings-nested']);

    // 7. Import a remote change → CrdtTextFieldBuilder adopts the merged
    //    value into the controller in place, still without rebuilding.
    before = snapshot();
    await tapButton(tester, 'Remote edit');
    expect(rebuilds(tester, 'note-text'), before['note-text']);
    expect(rebuilds(tester, 'document'), greaterThan(before['document']!));
    expect(rebuilds(tester, 'counter'), before['counter']);
    expect(rebuilds(tester, 'settings-flat'), before['settings-flat']);
    expect(rebuilds(tester, 'listener-child'), before['listener-child']);
    final field = tester.widget<TextField>(find.byKey(const Key('note-field')));
    expect(field.controller!.text, contains('[remote]'));
    expect(field.controller!.text, contains('hello world'));

    // 8. Toggle the fake collaborator cursor → only the overlay subtree
    //    rebuilds: the note-text badge (outside the ValueListenableBuilder)
    //    stays put, and painting a stable anchor raises no errors.
    before = snapshot();
    await tapButton(tester, 'Toggle cursor');
    expect(rebuilds(tester, 'note-text'), before['note-text']);
    expect(tester.takeException(), isNull);

    // 9. Presence overlay: a fake peer 'Bob' whose pointer is driven by a
    //    stream + timer. Starting it moves the cursor across the pane WITHOUT
    //    rebuilding the card subtree — the presence badge (outside the
    //    StreamBuilder) stays put while the overlay updates.
    before = snapshot();
    final startPresence = find.widgetWithText(FilledButton, 'Start presence');
    await tester.ensureVisible(startPresence);
    await tester.tap(startPresence);
    await tester.pump(); // apply setState (badge +1), start the timer
    expect(rebuilds(tester, 'presence'), before['presence']! + 1);
    await tester.pump(const Duration(milliseconds: 120)); // first tick
    expect(find.text('Bob'), findsOneWidget);
    final movedBadge = rebuilds(tester, 'presence');
    await tester.pump(const Duration(milliseconds: 120)); // cursor glides
    expect(rebuilds(tester, 'presence'), movedBadge); // no rebuild on move
    expect(tester.takeException(), isNull);
    // Stop the timer so the test can settle and end cleanly.
    await tester.tap(find.widgetWithText(FilledButton, 'Stop presence'));
    await tester.pump();
    expect(find.text('Bob'), findsNothing);

    // 10. History: the call to action opens a page that draws the counter and
    //     the todos with the same widgets, frozen at a snapshot.
    before = snapshot();
    await tapButton(tester, 'Version history');
    Finder inPage(Finder finder) => find.descendant(
      of: find.byKey(const Key('history-page')),
      matching: finder,
    );
    expect(inPage(find.text('Todo #1 ✎')), findsOneWidget);
    expect(inPage(find.text('value: 1')), findsOneWidget);

    // The slider moves the cursor: at the start the document is empty.
    tester.widget<Slider>(find.byKey(const Key('history-slider'))).onChanged!(
      0,
    );
    await tester.pumpAndSettle();
    expect(inPage(find.text('No todos yet')), findsOneWidget);
    expect(inPage(find.text('value: 0')), findsOneWidget);
    expect(find.textContaining('change 0 of'), findsOneWidget);

    String info() =>
        tester.widget<Text>(find.byKey(const Key('history-change-info'))).data!;
    expect(info(), 'Initial state');

    await tapButton(tester, 'Step forward');
    expect(find.textContaining('change 1 of'), findsOneWidget);
    // The author (short peer id) and the time of the change.
    expect(info(), matches(RegExp(r'^[0-9a-f]{8} · \d{4}-\d{2}-\d{2} ')));

    // Closing the page leaves the live cards as they were.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(rebuilds(tester, 'todos-list'), before['todos-list']);
    expect(rebuilds(tester, 'counter'), before['counter']);

    // Flush the SnackBar auto-dismiss timer so the test ends cleanly.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
