// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_lf_recipes/todo_aggregate/main.dart' as app;
import 'package:crdt_lf_recipes/todo_aggregate/todo_page.dart';
import 'package:crdt_lf_recipes/todo_aggregate/todos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The text of every todo of [document], in order.
List<String> textsOf(CRDTDocument document) => [
  for (final todo in todosOf(document).value.todos) todo.text,
];

/// Sends to each document what the other is missing.
void exchange(CRDTDocument a, CRDTDocument b) {
  a.importChanges(b.exportChanges());
  b.importChanges(a.exportChanges());
}

void main() {
  testWidgets('adds, edits, checks, reorders, deletes and undoes', (
    tester,
  ) async {
    app.main();
    await tester.pump();
    final document = CrdtProvider.of(tester.element(find.byType(TodoPage)));

    for (final text in ['Milk', 'Eggs', 'Bread']) {
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField).last, text);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
    }
    expect(textsOf(document), ['Milk', 'Eggs', 'Bread']);

    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pump();
    expect(todosOf(document).value.todos[1].done, isTrue);

    // What a drag of Milk below Bread reports.
    tester
        .widget<ReorderableListView>(find.byType(ReorderableListView))
        .onReorderItem!(0, 2);
    await tester.pump();
    expect(textsOf(document), ['Eggs', 'Bread', 'Milk']);

    await tester.tap(find.byTooltip('Delete').first);
    await tester.pump();
    expect(textsOf(document), ['Bread', 'Milk']);

    // The undo puts Eggs back in its place, still done.
    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect(textsOf(document), ['Eggs', 'Bread', 'Milk']);
    expect(todosOf(document).value.todos.first.done, isTrue);

    await tester.tap(find.byTooltip('Redo'));
    await tester.pump();
    expect(textsOf(document), ['Bread', 'Milk']);
  });

  group('two peers', () {
    late CRDTDocument alice;
    late CRDTDocument bob;

    setUp(() {
      // Pinned ids: the replay order of concurrent events depends on them.
      alice = CRDTDocument(
        peerId: PeerId.parse('00000000-0000-4000-8000-000000000001'),
      );
      bob = CRDTDocument(
        peerId: PeerId.parse('00000000-0000-4000-8000-000000000002'),
      );
    });

    tearDown(() {
      alice.dispose();
      bob.dispose();
    });

    test('two moves of the same todo leave it once', () {
      final todos = todosOf(alice);
      final ids = [
        for (final text in ['a', 'b', 'c']) todos.dispatch(TodoAdded(text)),
      ];
      exchange(alice, bob);

      // Both move "a": Alice after "c", Bob after "b".
      todosOf(alice).dispatch(TodoMoved(ids[0], after: ids[2]));
      todosOf(bob).dispatch(TodoMoved(ids[0], after: ids[1]));
      exchange(alice, bob);

      expect(textsOf(alice), textsOf(bob));
      expect(textsOf(alice), unorderedEquals(['a', 'b', 'c']));
    });

    test('an edit of a todo another peer removed does nothing', () {
      final id = todosOf(alice).dispatch(const TodoAdded('Milk'));
      exchange(alice, bob);

      todosOf(alice).dispatch(TodoRemoved(id));
      todosOf(bob).dispatch(TodoChecked(id, done: true));
      exchange(alice, bob);

      expect(textsOf(alice), isEmpty);
      expect(textsOf(bob), isEmpty);
    });

    test('an undo reaches the other peer', () {
      final todos = todosOf(alice);
      final undo = CRDTUndoManager(alice, captureTimeout: Duration.zero)
        ..track(todos);
      addTearDown(undo.dispose);
      final id = todos.dispatch(const TodoAdded('Milk'));
      todos
        ..dispatch(TodoEdited(id, 'Oat milk'))
        ..dispatch(TodoRemoved(id));
      exchange(alice, bob);
      expect(textsOf(bob), isEmpty);

      undo
        ..undo() // the remove
        ..undo(); // the edit
      exchange(alice, bob);
      expect(textsOf(bob), ['Milk']);
    });

    test('a snapshot keeps the ids the next events address', () {
      final id = todosOf(alice).dispatch(const TodoAdded('Milk'));
      final snapshot = alice.takeSnapshot();

      bob.importSnapshot(snapshot);
      todosOf(bob).dispatch(TodoEdited(id, 'Oat milk'));
      expect(textsOf(bob), ['Oat milk']);
    });
  });
}
