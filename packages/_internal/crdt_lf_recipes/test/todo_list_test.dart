// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_lf_recipes/todo_list/main.dart' as app;
import 'package:crdt_lf_recipes/todo_list/todo_page.dart';
import 'package:crdt_lf_recipes/todo_list/todos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The text of every todo of [document], in order.
List<String> textsOf(CRDTDocument document) => [
  for (final todo in todosOf(document).children.whereType<CRDTMapRefHandler>())
    todo.text.value,
];

/// Sends to each document what the other is missing.
void exchange(CRDTDocument a, CRDTDocument b) {
  a.importChanges(b.exportChanges());
  b.importChanges(a.exportChanges());
}

void main() {
  testWidgets('the app provides an empty list to the page', (tester) async {
    app.main();
    await tester.pump();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    expect(find.byType(TodoTile), findsOneWidget);
  });

  group('the page', () {
    late CRDTDocument document;

    setUp(() {
      document = CRDTDocument();
      todosOf(document);
    });

    tearDown(() => document.dispose());

    Future<void> pumpPage(WidgetTester tester) {
      return tester.pumpWidget(
        MaterialApp(
          home: CrdtProvider.value(value: document, child: const TodoPage()),
        ),
      );
    }

    testWidgets('adds, edits, checks, reorders and deletes todos', (
      tester,
    ) async {
      await pumpPage(tester);

      for (final text in ['Milk', 'Eggs', 'Bread']) {
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pump();
        await tester.enterText(find.byType(TextField).last, text);
      }
      expect(textsOf(document), ['Milk', 'Eggs', 'Bread']);

      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pump();
      final eggs = todosOf(document).getRefAtAs<CRDTMapRefHandler>(1)!;
      expect(eggs.done.value, isTrue);

      // What a drag of Milk below Bread reports.
      tester
          .widget<ReorderableListView>(find.byType(ReorderableListView))
          .onReorderItem!(0, 2);
      await tester.pump();
      expect(textsOf(document), ['Eggs', 'Bread', 'Milk']);
      expect(
        tester.widgetList<Checkbox>(find.byType(Checkbox)).map((c) => c.value),
        [true, false, false],
      );

      await tester.tap(find.byTooltip('Delete').first);
      await tester.pump();
      expect(textsOf(document), ['Bread', 'Milk']);
      expect(find.byType(TextField), findsNWidgets(2));
    });
    testWidgets('a child that is not a todo keeps the tile indexes right', (
      tester,
    ) async {
      final todos = todosOf(document);
      for (final text in ['Milk', 'Eggs']) {
        addTodo(todos, text: text);
      }
      // What a newer peer could write: a child of another kind.
      todos.insertChild(0, CRDTFugueTextHandler.spec);
      await pumpPage(tester);

      expect(find.text('Unknown item'), findsOneWidget);

      await tester.tap(find.byTooltip('Delete').first);
      await tester.pump();
      expect(textsOf(document), ['Eggs']);
    });
  });

  group('two peers', () {
    late CRDTDocument alice;
    late CRDTDocument bob;

    setUp(() {
      // Pinned ids: the order of concurrent edits depends on them.
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

    test('a toggle and a text edit on the same todo both survive', () {
      addTodo(todosOf(alice), text: 'Buy milk');
      exchange(alice, bob);

      // At the same time, on the same todo.
      todosOf(alice).getRefAtAs<CRDTMapRefHandler>(0)!.done.set(true);
      todosOf(
        bob,
      ).getRefAtAs<CRDTMapRefHandler>(0)!.text.insert(8, ' and eggs');
      exchange(alice, bob);

      for (final peer in [alice, bob]) {
        expect(todosOf(peer).resolved, [
          {'text': 'Buy milk and eggs', 'done': true},
        ]);
      }
    });

    test('two moves of the same todo leave it once', () {
      final todos = todosOf(alice);
      for (final text in ['a', 'b', 'c']) {
        addTodo(todos, text: text);
      }
      exchange(alice, bob);

      // Both move "a", to two different places.
      todosOf(alice).move(0, 2);
      todosOf(bob).move(0, 1);
      exchange(alice, bob);

      expect(textsOf(alice), textsOf(bob));
      expect(textsOf(alice), unorderedEquals(['a', 'b', 'c']));
    });
  });
}
